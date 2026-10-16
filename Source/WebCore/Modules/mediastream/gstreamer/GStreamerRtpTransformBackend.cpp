/*
 *  Copyright (C) 2021-2022 Igalia S.L. All rights reserved.
 *  Copyright (C) 2022 Metrological Group B.V.
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

#include "config.h"
#include "GStreamerRtpTransformBackend.h"

#if ENABLE(WEB_RTC) && USE(GSTREAMER_WEBRTC)

#include "RTCRtpTransformableFrame.h"
#include <gst/rtp/gstrtpbuffer.h>
#include <wtf/NeverDestroyed.h>
#include <wtf/StdLibExtras.h>
#include <wtf/WorkQueue.h>
#include <atomic>
#include <memory>

namespace WebCore {

// Opus has one encoded frame per RTP payload. Video requires frame reassembly
// before the worker boundary and is deliberately not handled by this bridge.
class GStreamerAudioTransformableFrame final : public RTCRtpTransformableFrame {
public:
    GStreamerAudioTransformableFrame(GstBuffer* buffer, GstPad* output, uint64_t generation, std::shared_ptr<std::atomic<unsigned>> pending)
        : m_buffer(buffer)
        , m_output(output)
        , m_generation(generation)
        , m_pending(WTF::move(pending))
    {
        ++*m_pending;
        GstRTPBuffer rtp = GST_RTP_BUFFER_INIT;
        if (!gst_rtp_buffer_map(buffer, GST_MAP_READ, &rtp))
            return;
        auto size = gst_rtp_buffer_get_payload_len(&rtp);
        m_data.append(unsafeMakeSpan(static_cast<const uint8_t*>(gst_rtp_buffer_get_payload(&rtp)), size));
        m_header.resize(gst_rtp_buffer_get_header_len(&rtp));
        gst_buffer_extract(buffer, 0, m_header.mutableSpan().data(), m_header.size());
        m_header[0] &= ~0x20; // Padding is not part of the encoded frame.
        m_metadata.synchronizationSource = gst_rtp_buffer_get_ssrc(&rtp);
        m_metadata.payloadType = gst_rtp_buffer_get_payload_type(&rtp);
        m_metadata.sequenceNumber = gst_rtp_buffer_get_seq(&rtp);
        m_metadata.rtpTimestamp = gst_rtp_buffer_get_timestamp(&rtp);
        m_metadata.mimeType = "audio/opus"_s;
        Vector<uint32_t> sources;
        for (unsigned i = 0; i < gst_rtp_buffer_get_csrc_count(&rtp); ++i)
            sources.append(gst_rtp_buffer_get_csrc(&rtp, i));
        m_metadata.contributingSources = WTF::move(sources);
        gst_rtp_buffer_unmap(&rtp);
    }

    ~GStreamerAudioTransformableFrame() { didEnqueueToScript(); }
    void didEnqueueToScript() final
    {
        if (std::exchange(m_pendingBudget, false))
            --*m_pending;
    }
    std::span<const uint8_t> data() const final { return m_data.span(); }
    void setData(std::span<const uint8_t> data) final { m_data.clear(); m_data.append(data); }
    uint64_t timestamp() const final { return m_metadata.rtpTimestamp.value_or(0); }
    RTCEncodedAudioFrameMetadata audioMetadata() const final { return m_metadata; }
    RTCEncodedVideoFrameMetadata videoMetadata() const final { return { }; }
    bool isKeyFrame() const final { return false; }
    void setOptions(const RTCEncodedAudioFrameMetadata&) final { } // RTP identity remains immutable.
    void setOptions(const RTCEncodedVideoFrameMetadata&) final { }
    Ref<RTCRtpTransformableFrame> clone() final
    {
        auto copy = adoptRef(*new GStreamerAudioTransformableFrame(m_buffer.get(), m_output.get(), m_generation, m_pending));
        copy->setData(m_data.span());
        copy->didEnqueueToScript();
        return copy;
    }

    GRefPtr<GstBuffer> takeBuffer()
    {
        if (std::exchange(m_consumed, true) || m_header.isEmpty() || m_data.size() > 65535 - m_header.size())
            return nullptr;
        GRefPtr result = adoptGRef(gst_buffer_new_allocate(nullptr, m_header.size() + m_data.size(), nullptr));
        gst_buffer_copy_into(result.get(), m_buffer.get(), GST_BUFFER_COPY_METADATA, 0, -1);
        gst_buffer_fill(result.get(), 0, m_header.span().data(), m_header.size());
        gst_buffer_fill(result.get(), m_header.size(), m_data.span().data(), m_data.size());
        return result;
    }
    GstPad* output() const { return m_output.get(); }
    uint64_t generation() const { return m_generation; }

private:
    GRefPtr<GstBuffer> m_buffer;
    GRefPtr<GstPad> m_output;
    Vector<uint8_t> m_data;
    Vector<uint8_t> m_header;
    RTCEncodedAudioFrameMetadata m_metadata;
    uint64_t m_generation;
    std::shared_ptr<std::atomic<unsigned>> m_pending;
    bool m_consumed { false };
    bool m_pendingBudget { true };
};

class GStreamerRtpTransformState : public ThreadSafeRefCounted<GStreamerRtpTransformState> {
public:
    Lock lock;
    RTCRtpTransformBackend::Callback callback WTF_GUARDED_BY_LOCK(lock);
    bool active WTF_GUARDED_BY_LOCK(lock) { false };
    uint64_t generation WTF_GUARDED_BY_LOCK(lock) { 0 };
    std::shared_ptr<std::atomic<unsigned>> pending { std::make_shared<std::atomic<unsigned>>(0) };
    std::atomic<unsigned> queuedOutputs { 0 };
    RefPtr<WorkQueue> outputQueue WTF_GUARDED_BY_LOCK(lock);
};

static Ref<GStreamerRtpTransformState> stateFor(GstObject* object)
{
    static NeverDestroyed<Lock> creationLock;
    Locker locker { creationLock.get() };
    auto* state = static_cast<GStreamerRtpTransformState*>(g_object_get_data(G_OBJECT(object), "palladium-opus-transform"));
    if (!state) {
        Ref created = adoptRef(*new GStreamerRtpTransformState);
        state = &created.leakRef();
        g_object_set_data_full(G_OBJECT(object), "palladium-opus-transform", state, [](gpointer data) {
            static_cast<GStreamerRtpTransformState*>(data)->deref();
        });
    }
    return *state;
}

GStreamerRtpTransformBackend::GStreamerRtpTransformBackend(GstObject* object, Side side)
    : m_side(side)
    , m_state(stateFor(object))
    , m_isAudio(GPOINTER_TO_INT(g_object_get_data(G_OBJECT(object), "palladium-audio")))
{
    // Block payloads while the worker is being attached. Never send untransformed
    // audio after the application has requested an encoded transform.
    Locker locker { m_state->lock };
    m_state->active = true;
    ++m_state->generation;
}

GStreamerRtpTransformBackend::~GStreamerRtpTransformBackend() = default;

RTCRtpTransformBackend::MediaType GStreamerRtpTransformBackend::mediaType() const
{
    return m_isAudio ? MediaType::Audio : MediaType::Video;
}

void GStreamerRtpTransformBackend::setInputCallback(Callback&& callback)
{
    Locker locker { m_state->lock };
    m_state->callback = WTF::move(callback);
}

void GStreamerRtpTransformBackend::clearTransformableFrameCallback()
{
    Locker locker { m_state->lock };
    m_state->callback = { };
    // Keep this endpoint blocked after a worker closes. Replacing the transform
    // installs a new generation; closing a worker must not leak plaintext.
    ++m_state->generation;
}

void GStreamerRtpTransformBackend::processTransformedFrame(RTCRtpTransformableFrame& frame)
{
    if (!m_isAudio)
        return;
    auto& audio = static_cast<GStreamerAudioTransformableFrame&>(frame);
    auto buffer = audio.takeBuffer();
    if (!buffer)
        return;
    if (m_state->queuedOutputs.fetch_add(1) >= 128) {
        --m_state->queuedOutputs;
        return;
    }
    RefPtr<WorkQueue> queue;
    {
        Locker locker { m_state->lock };
        if (!m_state->outputQueue)
            m_state->outputQueue = WorkQueue::create("Palladium Opus transform"_s);
        queue = m_state->outputQueue;
    }
    queue->dispatch([state = m_state.copyRef(), output = GRefPtr(audio.output()), buffer = WTF::move(buffer), generation = audio.generation()]() mutable {
        {
            Locker locker { state->lock };
            if (generation != state->generation || !state->callback) {
                --state->queuedOutputs;
                return;
            }
        }
        // A serial queue preserves packet order without blocking the media thread
        // while JavaScript handles a frame. The sink pad serializes against flush.
        if (gst_pad_is_active(output.get()) && gst_pad_is_linked(output.get()))
            gst_pad_chain(output.get(), buffer.leakRef());
        --state->queuedOutputs;
    });
}

void GStreamerRtpTransformBackend::installTransform(GstPad* pad, GstObject* object)
{
    if (!pad || !object || g_object_get_data(G_OBJECT(pad), "palladium-opus-probe"))
        return;
    g_object_set_data(G_OBJECT(pad), "palladium-opus-probe", GINT_TO_POINTER(1));
    auto state = stateFor(object);
    gst_pad_add_probe(pad, static_cast<GstPadProbeType>(GST_PAD_PROBE_TYPE_BUFFER | GST_PAD_PROBE_TYPE_BUFFER_LIST), [](GstPad* pad, GstPadProbeInfo* info, gpointer data) -> GstPadProbeReturn {
        auto& state = *static_cast<GStreamerRtpTransformState*>(data);
        Locker locker { state.lock };
        if (!state.active)
            return GST_PAD_PROBE_OK;
        if (!state.callback || *state.pending >= 128)
            return GST_PAD_PROBE_DROP;
        GRefPtr caps = adoptGRef(gst_pad_get_current_caps(pad));
        const auto* structure = caps && !gst_caps_is_empty(caps.get()) ? gst_caps_get_structure(caps.get(), 0) : nullptr;
        if (!structure || g_strcmp0(gst_structure_get_string(structure, "encoding-name"), "OPUS"))
            return GST_PAD_PROBE_DROP;
        GRefPtr output = adoptGRef(gst_pad_get_peer(pad));
        if (!output)
            return GST_PAD_PROBE_DROP;
        auto transform = [&](GstBuffer* buffer) {
            if (*state.pending < 128)
                state.callback(adoptRef(*new GStreamerAudioTransformableFrame(buffer, output.get(), state.generation, state.pending)));
        };
        if (info->type & GST_PAD_PROBE_TYPE_BUFFER_LIST) {
            auto* list = GST_PAD_PROBE_INFO_BUFFER_LIST(info);
            for (unsigned i = 0; i < gst_buffer_list_length(list); ++i)
                transform(gst_buffer_list_get(list, i));
        } else
            transform(GST_PAD_PROBE_INFO_BUFFER(info));
        return GST_PAD_PROBE_DROP;
    }, &state.leakRef(), [](gpointer data) { static_cast<GStreamerRtpTransformState*>(data)->deref(); });
}

} // namespace WebCore

#endif // ENABLE(WEB_RTC) && USE(GSTREAMER_WEBRTC)
