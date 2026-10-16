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

#pragma once

#if ENABLE(WEB_RTC) && USE(GSTREAMER_WEBRTC)

#include "RTCRtpTransformBackend.h"
#include "GRefPtrGStreamer.h"
#include <wtf/Lock.h>

namespace WebCore {

class GStreamerRtpTransformState;

class GStreamerRtpTransformBackend : public RTCRtpTransformBackend {
public:
    ~GStreamerRtpTransformBackend();
    static void installTransform(GstPad*, GstObject*);

protected:
    GStreamerRtpTransformBackend(GstObject*, Side);
    void setInputCallback(Callback&&);

protected:
    MediaType mediaType() const final;

private:
    // RTCRtpTransformBackend
    void processTransformedFrame(RTCRtpTransformableFrame&) final;
    void clearTransformableFrameCallback() final;
    Side side() const final { return m_side; }

    Side m_side;
    Ref<GStreamerRtpTransformState> m_state;
    bool m_isAudio;
    uint64_t m_generation { 0 };
};

} // namespace WebCore

#endif // ENABLE(WEB_RTC) && USE(GSTREAMER_WEBRTC)
