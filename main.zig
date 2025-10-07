const std = @import("std");
const fatal = std.process.fatal;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stdout_writer_state = std.fs.File.stdout().writer(&.{});
    const stdout = &stdout_writer_state.interface;

    if (args.len > 2) fatal("expected none or one device path like /dev/video*", .{});
    const dev_path = if (args.len == 2) args[1] else "/dev/video0";

    try stdout.print("opening {s}device {s}\n", .{ if (args.len != 2) "default " else "", dev_path });

    const dev = std.fs.cwd().openFile(dev_path, .{ .mode = .read_write }) catch |err|
        fatal("{s}: {t}", .{ dev_path, err });
    defer dev.close();

    const caps = v4l.queryCaps(dev) catch |err| fatal("{s}: {t}", .{ dev_path, err });

    if (!caps.capabilities.video_capture) fatal("{s} is not a video capture device", .{dev_path});
    if (!caps.capabilities.streaming) fatal("{s} does not support streaming", .{dev_path});

    const fmt = try v4l.getFormat(dev, .video_capture) orelse
        fatal("{s} has no video_capture format", .{dev_path});

    const reqbufs = try v4l.requestBuffers(dev, .video_capture, .mmap, 1);
    if (reqbufs.count != 1) fatal("got {} instead of 1 buffer", .{reqbufs.count});

    const qb = try v4l.queryBuffer(dev, .video_capture, .mmap, 0);

    const rw = std.os.linux.PROT.READ | std.os.linux.PROT.WRITE;
    const mem = try std.posix.mmap(null, qb.length, rw, .{ .TYPE = .SHARED }, dev.handle, qb.m.offset);
    defer std.posix.munmap(mem);

    _ = try v4l.queueBuffer(dev, .video_capture, .mmap, 0);
    try v4l.startStreaming(dev, .video_capture);
    _ = try v4l.dequeueBuffer(dev, .video_capture, .mmap);
    try v4l.stopStreaming(dev, .video_capture);

    try stdout.print("captured image has pix_fmt: {t}, size: {}x{}\n", .{ fmt.pixelformat, fmt.width, fmt.height });
    try stdout.print("saving image to img.raw\n", .{});

    std.fs.cwd().writeFile(
        .{ .sub_path = "img.raw", .data = mem, .flags = .{ .exclusive = true } },
    ) catch |err| switch (err) {
        error.PathAlreadyExists => fatal("img.raw already exists", .{}),
        else => return err,
    };
}

// from include/linux/videodev2.h
// and linux docs
const v4l = struct {
    const IoctlRequest = enum(u32) {
        const IOCTL = std.os.linux.IOCTL;

        querycap = IOCTL.IOR('V', 0, Capability),
        enum_fmt = IOCTL.IOWR('V', 2, Fmtdesc),
        g_fmt = IOCTL.IOWR('V', 4, Format),
        s_fmt = IOCTL.IOWR('V', 5, Format),
        reqbufs = IOCTL.IOWR('V', 8, RequestBuffers),
        querybuf = IOCTL.IOWR('V', 9, Buffer),
        // g_fbuf=  IOCTL.IOR('V', 10, struct v4l2_framebuffer),
        // s_fbuf=  IOCTL.IOW('V', 11, struct v4l2_framebuffer),
        // overlay=  IOCTL.IOW('V', 14, int),
        qbuf = IOCTL.IOWR('V', 15, Buffer),
        // expbuf= IOCTL.IOWR('V', 16, struct v4l2_exportbuffer),
        dqbuf = IOCTL.IOWR('V', 17, Buffer),
        streamon = IOCTL.IOW('V', 18, c_int),
        streamoff = IOCTL.IOW('V', 19, c_int),
        // g_parm= IOCTL.IOWR('V', 21, struct v4l2_streamparm),
        // s_parm= IOCTL.IOWR('V', 22, struct v4l2_streamparm),
        // g_std=  IOCTL.IOR('V', 23, v4l2_std_id),
        // s_std=  IOCTL.IOW('V', 24, v4l2_std_id),
        // enumstd= IOCTL.IOWR('V', 25, struct v4l2_standard),
        // enuminput= IOCTL.IOWR('V', 26, struct v4l2_input),
        // g_ctrl= IOCTL.IOWR('V', 27, struct v4l2_control),
        // s_ctrl= IOCTL.IOWR('V', 28, struct v4l2_control),
        // g_tuner= IOCTL.IOWR('V', 29, struct v4l2_tuner),
        // s_tuner=  IOCTL.IOW('V', 30, struct v4l2_tuner),
        // g_audio=  IOCTL.IOR('V', 33, struct v4l2_audio),
        // s_audio=  IOCTL.IOW('V', 34, struct v4l2_audio),
        // queryctrl= IOCTL.IOWR('V', 36, struct v4l2_queryctrl),
        // querymenu= IOCTL.IOWR('V', 37, struct v4l2_querymenu),
        // g_input=  IOCTL.IOR('V', 38, int),
        // s_input= IOCTL.IOWR('V', 39, int),
        // g_edid= IOCTL.IOWR('V', 40, struct v4l2_edid),
        // s_edid= IOCTL.IOWR('V', 41, struct v4l2_edid),
        // g_output=  IOCTL.IOR('V', 46, int),
        // s_output= IOCTL.IOWR('V', 47, int),
        // enumoutput= IOCTL.IOWR('V', 48, struct v4l2_output),
        // g_audout=  IOCTL.IOR('V', 49, struct v4l2_audioout),
        // s_audout=  IOCTL.IOW('V', 50, struct v4l2_audioout),
        // g_modulator= IOCTL.IOWR('V', 54, struct v4l2_modulator),
        // s_modulator=  IOCTL.IOW('V', 55, struct v4l2_modulator),
        // g_frequency= IOCTL.IOWR('V', 56, struct v4l2_frequency),
        // s_frequency=  IOCTL.IOW('V', 57, struct v4l2_frequency),
        // cropcap= IOCTL.IOWR('V', 58, struct v4l2_cropcap),
        // g_crop= IOCTL.IOWR('V', 59, struct v4l2_crop),
        // s_crop=  IOCTL.IOW('V', 60, struct v4l2_crop),
        // g_jpegcomp=  IOCTL.IOR('V', 61, struct v4l2_jpegcompression),
        // s_jpegcomp=  IOCTL.IOW('V', 62, struct v4l2_jpegcompression),
        // querystd=  IOCTL.IOR('V', 63, v4l2_std_id),
        // try_fmt= IOCTL.IOWR('V', 64, struct v4l2_format),
        // enumaudio= IOCTL.IOWR('V', 65, struct v4l2_audio),
        // enumaudout= IOCTL.IOWR('V', 66, struct v4l2_audioout),
        // g_priority=  IOCTL.IOR('V', 67, __u32), /* enum v4l2_priority */
        // s_priority=  IOCTL.IOW('V', 68, __u32), /* enum v4l2_priority */
        // g_sliced_vbi_cap=  IOCTL.IOWR('V', 69, struct v4l2_sliced_vbi_cap),
        // log_status        =  IOCTL.IO('V', 70),
        // g_ext_ctrls= IOCTL.IOWR('V', 71, struct v4l2_ext_controls),
        // s_ext_ctrls= IOCTL.IOWR('V', 72, struct v4l2_ext_controls),
        // try_ext_ctrls= IOCTL.IOWR('V', 73, struct v4l2_ext_controls),
        // enum_framesizes= IOCTL.IOWR('V', 74, struct v4l2_frmsizeenum),
        // enum_frameintervals=  IOCTL.IOWR('V', 75, struct v4l2_frmivalenum),
        // g_enc_index      =  IOCTL.IOR('V', 76, struct v4l2_enc_idx),
        // encoder_cmd     =  IOCTL.IOWR('V', 77, struct v4l2_encoder_cmd),
        // try_encoder_cmd =  IOCTL.IOWR('V', 78, struct v4l2_encoder_cmd),
    };

    fn ioctl(f: std.fs.File, r: IoctlRequest, arg: *anyopaque) !void {
        const rc = std.os.linux.ioctl(f.handle, @intFromEnum(r), @intFromPtr(arg));
        switch (std.os.linux.E.init(rc)) {
            .SUCCESS => {},
            .BADF => unreachable,
            .FAULT => unreachable,
            .INVAL => return error.Invalid, // meaning depends on ioctl call
            .PERM => return error.PermissionDenied,
            .NOTTY => return error.UnsupportedIoctlRequest, // driver does not support the request
            else => |err| return std.posix.unexpectedErrno(err),
        }
    }

    const Capability = extern struct {
        driver: [16]u8, // name of driver module
        card: [32]u8, // name of card
        bus_info: [32]u8, // name of bus
        version: u32, // kernel version
        capabilities: Capabilities, // physical device capabilities
        device_caps: Capabilities, // capabilities of this node

        reserved: [3]u32,

        const Capabilities = packed struct(u32) {
            video_capture: bool,
            video_output: bool,
            video_overlay: bool,
            _4: u1,
            vbi_capture: bool,
            vbi_output: bool,
            sliced_vbi_capture: bool,
            sliced_vbi_output: bool,
            rds_capture: bool,
            video_output_overlay: bool,
            hw_freq_seek: bool,
            rds_output: bool,
            video_capture_mplane: bool,
            video_output_mplane: bool,
            video_m2m_mplane: bool,
            video_m2m: bool,
            tuner: bool,
            audio: bool,
            radio: bool,
            modulator: bool,
            sdr_capture: bool,
            ext_pix_format: bool,
            sdt_output: bool,
            meta_capture: bool,
            readwrite: bool,
            edid: bool,
            streaming: bool,
            meta_output: bool,
            touch: bool,
            io_mc: bool,
            _31: u1,
            device_caps: bool, //sets device_caps field
        };
        pub fn driverName(c: *const Capability) []const u8 {
            return std.mem.sliceTo(&c.driver, 0);
        }

        pub fn cardName(c: *const Capability) []const u8 {
            return std.mem.sliceTo(&c.card, 0);
        }

        pub fn busName(c: *const Capability) []const u8 {
            return std.mem.sliceTo(&c.bus_info, 0);
        }
    };

    pub fn queryCaps(f: std.fs.File) !Capability {
        var cap: Capability = undefined;
        try ioctl(f, .querycap, &cap);
        return cap;
    }
    pub fn fourcc(b: *const [4]u8) u32 {
        return std.mem.readInt(u32, b, .little);
    }
    pub fn fourccBe(b: *const [4]u8) u32 {
        return fourcc(b) | 1 << 31;
    }

    const FourccPixFmt = enum(u32) {
        // RGB formats (1 or 2 bytes per pixel)
        RGB332 = fourcc("RGB1"), //  8  RGB-3-3-2
        RGB444 = fourcc("R444"), // 16  xxxxrrrr ggggbbbb
        ARGB444 = fourcc("AR12"), // 16  aaaarrrr ggggbbbb
        XRGB444 = fourcc("XR12"), // 16  xxxxrrrr ggggbbbb
        RGBA444 = fourcc("RA12"), // 16  rrrrgggg bbbbaaaa
        RGBX444 = fourcc("RX12"), // 16  rrrrgggg bbbbxxxx
        ABGR444 = fourcc("AB12"), // 16  aaaabbbb ggggrrrr
        XBGR444 = fourcc("XB12"), // 16  xxxxbbbb ggggrrrr
        BGRA444 = fourcc("GA12"), // 16  bbbbgggg rrrraaaa
        BGRX444 = fourcc("BX12"), // 16  bbbbgggg rrrrxxxx
        RGB555 = fourcc("RGBO"), // 16  RGB-5-5-5
        ARGB555 = fourcc("AR15"), // 16  ARGB-1-5-5-5
        XRGB555 = fourcc("XR15"), // 16  XRGB-1-5-5-5
        RGBA555 = fourcc("RA15"), // 16  RGBA-5-5-5-1
        RGBX555 = fourcc("RX15"), // 16  RGBX-5-5-5-1
        ABGR555 = fourcc("AB15"), // 16  ABGR-1-5-5-5
        XBGR555 = fourcc("XB15"), // 16  XBGR-1-5-5-5
        BGRA555 = fourcc("BA15"), // 16  BGRA-5-5-5-1
        BGRX555 = fourcc("BX15"), // 16  BGRX-5-5-5-1
        RGB565 = fourcc("RGBP"), // 16  RGB-5-6-5
        RGB555X = fourcc("RGBQ"), // 16  RGB-5-5-5 BE
        ARGB555X = fourccBe("AR15"), // 16  ARGB-5-5-5 BE
        XRGB555X = fourccBe("XR15"), // 16  XRGB-5-5-5 BE
        RGB565X = fourcc("RGBR"), // 16  RGB-5-6-5 BE

        // RGB formats (3 or 4 bytes per pixel)
        BGR666 = fourcc("BGRH"), // 18  BGR-6-6-6
        BGR24 = fourcc("BGR3"), // 24  BGR-8-8-8
        RGB24 = fourcc("RGB3"), // 24  RGB-8-8-8
        BGR32 = fourcc("BGR4"), // 32  BGR-8-8-8-8
        ABGR32 = fourcc("AR24"), // 32  BGRA-8-8-8-8
        XBGR32 = fourcc("XR24"), // 32  BGRX-8-8-8-8
        BGRA32 = fourcc("RA24"), // 32  ABGR-8-8-8-8
        BGRX32 = fourcc("RX24"), // 32  XBGR-8-8-8-8
        RGB32 = fourcc("RGB4"), // 32  RGB-8-8-8-8
        RGBA32 = fourcc("AB24"), // 32  RGBA-8-8-8-8
        RGBX32 = fourcc("XB24"), // 32  RGBX-8-8-8-8
        ARGB32 = fourcc("BA24"), // 32  ARGB-8-8-8-8
        XRGB32 = fourcc("BX24"), // 32  XRGB-8-8-8-8
        RGBX1010102 = fourcc("RX30"), // 32  RGBX-10-10-10-2
        RGBA1010102 = fourcc("RA30"), // 32  RGBA-10-10-10-2
        ARGB2101010 = fourcc("AR30"), // 32  ARGB-2-10-10-10

        // RGB formats (6 or 8 bytes per pixel)
        BGR48_12 = fourcc("B312"), // 48  BGR 12-bit per component
        BGR48 = fourcc("BGR6"), // 48  BGR 16-bit per component
        RGB48 = fourcc("RGB6"), // 48  RGB 16-bit per component
        ABGR64_12 = fourcc("B412"), // 64  BGRA 12-bit per component

        // Grey formats
        GREY = fourcc("GREY"), //  8  Greyscale
        Y4 = fourcc("Y04 "), //  4  Greyscale
        Y6 = fourcc("Y06 "), //  6  Greyscale
        Y10 = fourcc("Y10 "), // 10  Greyscale
        Y12 = fourcc("Y12 "), // 12  Greyscale
        Y012 = fourcc("Y012"), // 12  Greyscale
        Y14 = fourcc("Y14 "), // 14  Greyscale
        Y16 = fourcc("Y16 "), // 16  Greyscale
        Y16_BE = fourccBe("Y16 "), // 16  Greyscale BE

        // Grey bit-packed formats
        Y10BPACK = fourcc("Y10B"), // 10  Greyscale bit-packed
        Y10P = fourcc("Y10P"), // 10  Greyscale, MIPI RAW10 packed
        IPU3_Y10 = fourcc("ip3y"), // IPU3 packed 10-bit greyscale
        Y12P = fourcc("Y12P"), // 12  Greyscale, MIPI RAW12 packed
        Y14P = fourcc("Y14P"), // 14  Greyscale, MIPI RAW14 packed

        // Palette formats
        PAL8 = fourcc("PAL8"), //  8  8-bit palette

        // Chrominance formats
        UV8 = fourcc("UV8 "), //  8  UV 4:4

        // Luminance+Chrominance formats
        YUYV = fourcc("YUYV"), // 16  YUV 4:2:2
        YYUV = fourcc("YYUV"), // 16  YUV 4:2:2
        YVYU = fourcc("YVYU"), // 16 YVU 4:2:2
        UYVY = fourcc("UYVY"), // 16  YUV 4:2:2
        VYUY = fourcc("VYUY"), // 16  YUV 4:2:2
        Y41P = fourcc("Y41P"), // 12  YUV 4:1:1
        YUV444 = fourcc("Y444"), // 16  xxxxyyyy uuuuvvvv
        YUV555 = fourcc("YUVO"), // 16  YUV-5-5-5
        YUV565 = fourcc("YUVP"), // 16  YUV-5-6-5
        YUV24 = fourcc("YUV3"), // 24  YUV-8-8-8
        YUV32 = fourcc("YUV4"), // 32  YUV-8-8-8-8
        AYUV32 = fourcc("AYUV"), // 32  AYUV-8-8-8-8
        XYUV32 = fourcc("XYUV"), // 32  XYUV-8-8-8-8
        VUYA32 = fourcc("VUYA"), // 32  VUYA-8-8-8-8
        VUYX32 = fourcc("VUYX"), // 32  VUYX-8-8-8-8
        YUVA32 = fourcc("YUVA"), // 32  YUVA-8-8-8-8
        YUVX32 = fourcc("YUVX"), // 32  YUVX-8-8-8-8
        M420 = fourcc("M420"), // 12  YUV 4:2:0 2 lines y, 1 line uv interleaved
        YUV48_12 = fourcc("Y312"), // 48  YUV 4:4:4 12-bit per component

        // YCbCr packed format. For each Y2xx format, xx bits of valid data occupy the MSBs
        // of the 16 bit components, and 16-xx bits of zero padding occupy the LSBs.
        Y210 = fourcc("Y210"), // 32  YUYV 4:2:2
        Y212 = fourcc("Y212"), // 32  YUYV 4:2:2
        Y216 = fourcc("Y216"), // 32  YUYV 4:2:2

        // two planes -- one Y, one Cr + Cb interleaved
        NV12 = fourcc("NV12"), // 12  Y/CbCr 4:2:0
        NV21 = fourcc("NV21"), // 12  Y/CrCb 4:2:0
        NV15 = fourcc("NV15"), // 15  Y/CbCr 4:2:0 10-bit packed
        NV16 = fourcc("NV16"), // 16  Y/CbCr 4:2:2
        NV61 = fourcc("NV61"), // 16  Y/CrCb 4:2:2
        NV20 = fourcc("NV20"), // 20  Y/CbCr 4:2:2 10-bit packed
        NV24 = fourcc("NV24"), // 24  Y/CbCr 4:4:4
        NV42 = fourcc("NV42"), // 24  Y/CrCb 4:4:4
        P010 = fourcc("P010"), // 24  Y/CbCr 4:2:0 10-bit per component
        P012 = fourcc("P012"), // 24  Y/CbCr 4:2:0 12-bit per component

        // two non contiguous planes - one Y, one Cr + Cb interleaved
        NV12M = fourcc("NM12"), // 12  Y/CbCr 4:2:0
        NV21M = fourcc("NM21"), // 21  Y/CrCb 4:2:0
        NV16M = fourcc("NM16"), // 16  Y/CbCr 4:2:2
        NV61M = fourcc("NM61"), // 16  Y/CrCb 4:2:2
        P012M = fourcc("PM12"), // 24  Y/CbCr 4:2:0 12-bit per component

        // three planes - Y Cb, Cr
        YUV410 = fourcc("YUV9"), //  9  YUV 4:1:0
        YVU410 = fourcc("YVU9"), //  9  YVU 4:1:0
        YUV411P = fourcc("411P"), // 12  YVU411 planar
        YUV420 = fourcc("YU12"), // 12  YUV 4:2:0
        YVU420 = fourcc("YV12"), // 12  YVU 4:2:0
        YUV422P = fourcc("422P"), // 16  YVU422 planar

        // three non contiguous planes - Y, Cb, Cr
        YUV420M = fourcc("YM12"), // 12  YUV420 planar
        YVU420M = fourcc("YM21"), // 12  YVU420 planar
        YUV422M = fourcc("YM16"), // 16  YUV422 planar
        YVU422M = fourcc("YM61"), // 16  YVU422 planar
        YUV444M = fourcc("YM24"), // 24  YUV444 planar
        YVU444M = fourcc("YM42"), // 24  YVU444 planar

        // Tiled YUV formats
        NV12_4L4 = fourcc("VT12"), // 12  Y/CbCr 4:2:0  4x4 tiles
        NV12_16L16 = fourcc("HM12"), // 12  Y/CbCr 4:2:0 16x16 tiles
        NV12_32L32 = fourcc("ST12"), // 12  Y/CbCr 4:2:0 32x32 tiles
        NV15_4L4 = fourcc("VT15"), // 15 Y/CbCr 4:2:0 10-bit 4x4 tiles
        P010_4L4 = fourcc("T010"), // 12  Y/CbCr 4:2:0 10-bit 4x4 macroblocks
        NV12_8L128 = fourcc("AT12"), // Y/CbCr 4:2:0 8x128 tiles
        NV12_10BE_8L128 = fourccBe("AX12"), // Y/CbCr 4:2:0 10-bit 8x128 tiles

        // Tiled YUV formats, non contiguous planes
        NV12MT = fourcc("TM12"), // 12  Y/CbCr 4:2:0 64x32 tiles
        NV12MT_16X16 = fourcc("VM12"), // 12  Y/CbCr 4:2:0 16x16 tiles
        NV12M_8L128 = fourcc("NA12"), // Y/CbCr 4:2:0 8x128 tiles
        NV12M_10BE_8L128 = fourccBe("NT12"), // Y/CbCr 4:2:0 10-bit 8x128 tiles

        // Bayer formats - see http://www.siliconimaging.com/RGB%20Bayer.htm
        SBGGR8 = fourcc("BA81"), //  8  BGBG.. GRGR..
        SGBRG8 = fourcc("GBRG"), //  8  GBGB.. RGRG..
        SGRBG8 = fourcc("GRBG"), //  8  GRGR.. BGBG..
        SRGGB8 = fourcc("RGGB"), //  8  RGRG.. GBGB..
        SBGGR10 = fourcc("BG10"), // 10  BGBG.. GRGR..
        SGBRG10 = fourcc("GB10"), // 10  GBGB.. RGRG..
        SGRBG10 = fourcc("BA10"), // 10  GRGR.. BGBG..
        SRGGB10 = fourcc("RG10"), // 10  RGRG.. GBGB..

        // 10bit raw bayer packed, 5 bytes for every 4 pixels
        SBGGR10P = fourcc("pBAA"),
        SGBRG10P = fourcc("pGAA"),
        SGRBG10P = fourcc("pgAA"),
        SRGGB10P = fourcc("pRAA"),

        // 10bit raw bayer a-law compressed to 8 bits
        SBGGR10ALAW8 = fourcc("aBA8"),
        SGBRG10ALAW8 = fourcc("aGA8"),
        SGRBG10ALAW8 = fourcc("agA8"),
        SRGGB10ALAW8 = fourcc("aRA8"),

        // 10bit raw bayer DPCM compressed to 8 bits
        SBGGR10DPCM8 = fourcc("bBA8"),
        SGBRG10DPCM8 = fourcc("bGA8"),
        SGRBG10DPCM8 = fourcc("BD10"),
        SRGGB10DPCM8 = fourcc("bRA8"),
        SBGGR12 = fourcc("BG12"), // 12  BGBG.. GRGR..
        SGBRG12 = fourcc("GB12"), // 12  GBGB.. RGRG..
        SGRBG12 = fourcc("BA12"), // 12  GRGR.. BGBG..
        SRGGB12 = fourcc("RG12"), // 12  RGRG.. GBGB..

        // 12bit raw bayer packed, 6 bytes for every 4 pixels
        SBGGR12P = fourcc("pBCC"),
        SGBRG12P = fourcc("pGCC"),
        SGRBG12P = fourcc("pgCC"),
        SRGGB12P = fourcc("pRCC"),
        SBGGR14 = fourcc("BG14"), // 14  BGBG.. GRGR..
        SGBRG14 = fourcc("GB14"), // 14  GBGB.. RGRG..
        SGRBG14 = fourcc("GR14"), // 14  GRGR.. BGBG..
        SRGGB14 = fourcc("RG14"), // 14  RGRG.. GBGB..

        // 14bit raw bayer packed, 7 bytes for every 4 pixels
        SBGGR14P = fourcc("pBEE"),
        SGBRG14P = fourcc("pGEE"),
        SGRBG14P = fourcc("pgEE"),
        SRGGB14P = fourcc("pREE"),
        SBGGR16 = fourcc("BYR2"), // 16  BGBG.. GRGR..
        SGBRG16 = fourcc("GB16"), // 16  GBGB.. RGRG..
        SGRBG16 = fourcc("GR16"), // 16  GRGR.. BGBG..
        SRGGB16 = fourcc("RG16"), // 16  RGRG.. GBGB..

        // HSV formats
        HSV24 = fourcc("HSV3"),
        HSV32 = fourcc("HSV4"),

        // compressed formats
        MJPEG = fourcc("MJPG"), // Motion-JPEG
        JPEG = fourcc("JPEG"), // JFIF JPEG
        DV = fourcc("dvsd"), // 1394
        MPEG = fourcc("MPEG"), // MPEG-1/2/4 Multiplexed
        H264 = fourcc("H264"), // H264 with start codes
        H264_NO_SC = fourcc("AVC1"), // H264 without start codes
        H264_MVC = fourcc("M264"), // H264 MVC
        H263 = fourcc("H263"), // H263
        MPEG1 = fourcc("MPG1"), // MPEG-1 ES
        MPEG2 = fourcc("MPG2"), // MPEG-2 ES
        MPEG2_SLICE = fourcc("MG2S"), // MPEG-2 parsed slice data
        MPEG4 = fourcc("MPG4"), // MPEG-4 part 2 ES
        XVID = fourcc("XVID"), // Xvid
        VC1_ANNEX_G = fourcc("VC1G"), // SMPTE 421M Annex G compliant stream
        VC1_ANNEX_L = fourcc("VC1L"), // SMPTE 421M Annex L compliant stream
        VP8 = fourcc("VP80"), // VP8
        VP8_FRAME = fourcc("VP8F"), // VP8 parsed frame
        VP9 = fourcc("VP90"), // VP9
        VP9_FRAME = fourcc("VP9F"), // VP9 parsed frame
        HEVC = fourcc("HEVC"), // HEVC aka H.265
        FWHT = fourcc("FWHT"), // Fast Walsh Hadamard Transform (vicodec)
        FWHT_STATELESS = fourcc("SFWH"), // Stateless FWHT (vicodec)
        H264_SLICE = fourcc("S264"), // H264 parsed slices
        HEVC_SLICE = fourcc("S265"), // HEVC parsed slices
        AV1_FRAME = fourcc("AV1F"), // AV1 parsed frame
        SPK = fourcc("SPK0"), // Sorenson Spark
        RV30 = fourcc("RV30"), // RealVideo 8
        RV40 = fourcc("RV40"), // RealVideo 9 & 10

        // Vendor-specific formats
        CPIA1 = fourcc("CPIA"), // cpia1 YUV
        WNVA = fourcc("WNVA"), // Winnov hw compress
        SN9C10X = fourcc("S910"), // SN9C10x compression
        SN9C20X_I420 = fourcc("S920"), // SN9C20x YUV 4:2:0
        PWC1 = fourcc("PWC1"), // pwc older webcam
        PWC2 = fourcc("PWC2"), // pwc newer webcam
        ET61X251 = fourcc("E625"), // ET61X251 compression
        SPCA501 = fourcc("S501"), // YUYV per line
        SPCA505 = fourcc("S505"), // YYUV per line
        SPCA508 = fourcc("S508"), // YUVY per line
        SPCA561 = fourcc("S561"), // compressed GBRG bayer
        PAC207 = fourcc("P207"), // compressed BGGR bayer
        MR97310A = fourcc("M310"), // compressed BGGR bayer
        JL2005BCD = fourcc("JL20"), // compressed RGGB bayer
        SN9C2028 = fourcc("SONX"), // compressed GBRG bayer
        SQ905C = fourcc("905C"), // compressed RGGB bayer
        PJPG = fourcc("PJPG"), // Pixart 73xx JPEG
        OV511 = fourcc("O511"), // ov511 JPEG
        OV518 = fourcc("O518"), // ov518 JPEG
        STV0680 = fourcc("S680"), // stv0680 bayer
        TM6000 = fourcc("TM60"), // tm5600/tm60x0
        CIT_YYVYUY = fourcc("CITV"), // one line of Y then 1 line of VYUY
        KONICA420 = fourcc("KONI"), // YUV420 planar in blocks of 256 pixels
        JPGL = fourcc("JPGL"), // JPEG-Lite
        SE401 = fourcc("S401"), // se401 janggu compressed rgb
        S5C_UYVY_JPG = fourcc("S5CI"), // S5C73M3 interleaved UYVY/JPEG
        Y8I = fourcc("Y8I "), // Greyscale 8-bit L/R interleaved
        Y12I = fourcc("Y12I"), // Greyscale 12-bit L/R interleaved
        Y16I = fourcc("Y16I"), // Greyscale 16-bit L/R interleaved
        Z16 = fourcc("Z16 "), // Depth data 16-bit
        MT21C = fourcc("MT21"), // Mediatek compressed block mode
        MM21 = fourcc("MM21"), // Mediatek 8-bit block mode, two non-contiguous planes
        MT2110T = fourcc("MT2T"), // Mediatek 10-bit block tile mode
        MT2110R = fourcc("MT2R"), // Mediatek 10-bit block raster mode
        INZI = fourcc("INZI"), // Intel Planar Greyscale 10-bit and Depth 16-bit
        CNF4 = fourcc("CNF4"), // Intel 4-bit packed depth confidence information
        HI240 = fourcc("HI24"), // BTTV 8-bit dithered RGB
        QC08C = fourcc("Q08C"), // Qualcomm 8-bit compressed
        QC10C = fourcc("Q10C"), // Qualcomm 10-bit compressed
        AJPG = fourcc("AJPG"), // Aspeed JPEG
        HEXTILE = fourcc("HXTL"), // Hextile compressed

        // 10bit raw packed, 32 bytes for every 25 pixels, last LSB 6 bits unused
        IPU3_SBGGR10 = fourcc("ip3b"), // IPU3 packed 10-bit BGGR bayer
        IPU3_SGBRG10 = fourcc("ip3g"), // IPU3 packed 10-bit GBRG bayer
        IPU3_SGRBG10 = fourcc("ip3G"), // IPU3 packed 10-bit GRBG bayer
        IPU3_SRGGB10 = fourcc("ip3r"), // IPU3 packed 10-bit RGGB bayer

        // Raspberry Pi PiSP compressed formats.
        PISP_COMP1_RGGB = fourcc("PC1R"), // PiSP 8-bit mode 1 compressed RGGB bayer
        PISP_COMP1_GRBG = fourcc("PC1G"), // PiSP 8-bit mode 1 compressed GRBG bayer
        PISP_COMP1_GBRG = fourcc("PC1g"), // PiSP 8-bit mode 1 compressed GBRG bayer
        PISP_COMP1_BGGR = fourcc("PC1B"), // PiSP 8-bit mode 1 compressed BGGR bayer
        PISP_COMP1_MONO = fourcc("PC1M"), // PiSP 8-bit mode 1 compressed monochrome
        PISP_COMP2_RGGB = fourcc("PC2R"), // PiSP 8-bit mode 2 compressed RGGB bayer
        PISP_COMP2_GRBG = fourcc("PC2G"), // PiSP 8-bit mode 2 compressed GRBG bayer
        PISP_COMP2_GBRG = fourcc("PC2g"), // PiSP 8-bit mode 2 compressed GBRG bayer
        PISP_COMP2_BGGR = fourcc("PC2B"), // PiSP 8-bit mode 2 compressed BGGR bayer
        PISP_COMP2_MONO = fourcc("PC2M"), // PiSP 8-bit mode 2 compressed monochrome

        // priv field value to indicates that subsequent fields are valid.
        priv_magic = 0xfeedcafe,
    };

    // SDR formats - used only for Software Defined Radio devices
    const FourccSdrFmt = enum(u32) {
        CU8 = fourcc("CU08"), // IQ u8
        CU16LE = fourcc("CU16"), // IQ u16le
        CS8 = fourcc("CS08"), // complex s8
        CS14LE = fourcc("CS14"), // complex s14le
        RU12LE = fourcc("RU12"), // real u12le
        PCU16BE = fourcc("PC16"), // planar complex u16be
        PCU18BE = fourcc("PC18"), // planar complex u18be
        PCU20BE = fourcc("PC20"), // planar complex u20be
    };

    // Touch formats - used for Touch devices
    const FourccTchFmt = enum(u32) {
        DELTA_TD16 = fourcc("TD16"), // 16-bit signed deltas
        DELTA_TD08 = fourcc("TD08"), // 8-bit signed deltas
        TU16 = fourcc("TU16"), // 16-bit unsigned touch data
        TU08 = fourcc("TU08"), // 8-bit unsigned touch data
    };

    const FourccMetaFmt = enum(u32) {
        VSP1_HGO = fourcc("VSPH"), // R-Car VSP1 1-D Histogram
        VSP1_HGT = fourcc("VSPT"), // R-Car VSP1 2-D Histogram
        UVC = fourcc("UVCH"), // UVC Payload Header metadata
        D4XX = fourcc("D4XX"), // D4XX Payload Header metadata
        VIVID = fourcc("VIVD"), // Vivid Metadata

        // Vendor specific - used for RK_ISP1 camera sub-system
        RK_ISP1_PARAMS = fourcc("RK1P"), // Rockchip ISP1 3A Parameters
        RK_ISP1_STAT_3A = fourcc("RK1S"), // Rockchip ISP1 3A Statistics
        RK_ISP1_EXT_PARAMS = fourcc("RK1E"), // Rockchip ISP1 3a Extensible Parameters

        // Vendor specific - used for C3_ISP
        C3ISP_PARAMS = fourcc("C3PM"), // Amlogic C3 ISP Parameters
        C3ISP_STATS = fourcc("C3ST"), // Amlogic C3 ISP Statistics

        // Vendor specific - used for RaspberryPi PiSP
        RPI_BE_CFG = fourcc("RPBC"), // PiSP BE configuration
        RPI_FE_CFG = fourcc("RPFC"), // PiSP FE configuration
        RPI_FE_STATS = fourcc("RPFS"), // PiSP FE stats
    };

    const Fmtdesc = extern struct {
        index: u32, // format number
        buf_type: Format.BufType,
        flags: Flags,
        description_bytes: [32]u8,
        pixelformat: FourccPixFmt,
        mbus_code: u32,

        reserved: [3]u32,

        const Flags = packed struct(u32) {
            compressed: bool,
            emulated: bool,
            continuous_bytestream: bool,
            dyn_resolution: bool,
            enc_cap_frame_interval: bool,
            csc_colorspace: bool,
            csc_xfer_func: bool,
            csc_ycbcr_enc: bool, // same as csc_hsv_enc
            csc_quantization: bool,
            meta_line_based: bool,

            reserved: u22,
        };

        pub fn description(fd: *const Fmtdesc) []const u8 {
            return std.mem.sliceTo(&fd.description_bytes, 0);
        }
    };

    // returns null when indexing past the last format
    pub fn enumerateFormats(f: std.fs.File, bt: Format.BufType, index: u32) !?Fmtdesc {
        std.debug.assert(bt.enumerable());
        var fmtdesc: Fmtdesc = std.mem.zeroes(Fmtdesc);
        fmtdesc.index = index;
        fmtdesc.buf_type = bt;

        ioctl(f, .enum_fmt, &fmtdesc) catch |err| switch (err) {
            error.Invalid => return null,
            else => return err,
        };
        return fmtdesc;
    }

    const Format = extern struct {
        buf_type: BufType,
        // align(8), since the c version has union members with a bigger alignment in this field
        // and the ioctl request expects the size of Format to be 208 bytes
        raw_data: [200]u8 align(8),

        pub fn initEmpty(bt: BufType) Format {
            var fmt = std.mem.zeroes(Format);
            fmt.buf_type = bt;
            return fmt;
        }

        pub fn init(comptime bt: BufType, data: bt.DataType()) Format {
            var fmt = std.mem.zeroes(Format);
            fmt.buf_type = bt;
            const data_bytes = std.mem.toBytes(data);
            @memcpy(fmt.raw_data[0..data_bytes.len], &data_bytes);
            return fmt;
        }

        pub fn dataAs(f: *Format, comptime bt: BufType) *bt.DataType() {
            std.debug.assert(f.buf_type == bt);
            return @ptrCast(&f.raw_data);
        }

        const BufType = enum(u32) {
            video_capture = 1,
            video_output = 2,
            video_overlay = 3,
            vbi_capture = 4,
            vbi_output = 5,
            sliced_vbi_capture = 6,
            sliced_vbi_output = 7,
            video_output_overlay = 8,
            video_capture_mplane = 9,
            video_output_mplane = 10,
            sdr_capture = 11,
            sdr_output = 12,
            meta_capture = 13,
            meta_output = 14,

            pub fn DataType(comptime bt: BufType) type {
                return switch (bt) {
                    .video_capture => PixFormat,
                    // .video_capture_mplane => PixFormatMplane,
                    // .video_overlay => Window,
                    // .vbi_capture => VbiFormat,
                    // .sliced_vbi_capture => SlicedVbiFormat,
                    // .sdr_capture => SdrFormat,
                    // .meta_capture => MetaFormat,
                    else => @compileError("unsupported buffer type: " ++ @tagName(bt)),
                };
            }
            pub fn enumerable(bt: BufType) bool {
                return switch (bt) {
                    .video_capture,
                    .video_capture_mplane,
                    .video_output,
                    .video_output_mplane,
                    .video_overlay,
                    => true,
                    else => false,
                };
            }

            pub fn category(bt: BufType) enum { output, capture } {
                return switch (bt) {
                    .video_capture,
                    .video_overlay,
                    .vbi_capture,
                    .sliced_vbi_capture,
                    .video_capture_mplane,
                    .sdr_capture,
                    .meta_capture,
                    => .capture,
                    .video_output,
                    .vbi_output,
                    .sliced_vbi_output,
                    .video_output_overlay,
                    .video_output_mplane,
                    .sdr_output,
                    .meta_output,
                    => .output,
                };
            }
            pub fn isMultiplanar(bt: BufType) bool {
                return bt == .video_capture_mplane or bt == .video_output_mplane;
            }
        };
    };

    pub fn getFormat(f: std.fs.File, comptime bt: Format.BufType) !?bt.DataType() {
        var fmt: Format = .initEmpty(bt);
        ioctl(f, .g_fmt, &fmt) catch |err| switch (err) {
            error.Invalid => return null,
            else => return err,
        };
        return fmt.dataAs(bt).*;
    }

    pub fn setFormat(f: std.fs.File, comptime bt: Format.BufType, data: bt.DataType()) !void {
        var fmt: Format = .init(bt, data);
        try ioctl(f, .g_fmt, &fmt);
    }
    const Field = enum(u32) {
        any = 0, // driver can choose from none, top, bottom, interlaced depending on whatever it thinks is approximate
        none = 1, // this device has no fields ...
        top = 2, // top field only
        bottom = 3, // bottom field only
        interlaced = 4, // both fields interlaced
        seq_tb = 5, // both fields sequential into one buffer, top-bottom order
        seq_bt = 6, // same as above + bottom-top order
        alternate = 7, // both fields alternating into separate buffers
        interlaced_tb = 8, // both fields interlaced, top field first and the top field is transmitted first
        interlaced_bt = 9, // both fields interlaced, top field first and the bottom field is transmitted first
    };

    const PixFormat = extern struct {
        width: u32,
        height: u32,
        pixelformat: FourccPixFmt,
        field: Field,
        bytesperline: u32, // padding, zero if unused
        sizeimage: u32,
        colorspace: Colorspace, // supplemental for pixelformat
        priv: u32, // content depends on pixelformat
        flags: Flags,
        enc: Encoding,
        quantization: Quantization,
        xfer_func: XferFunc,

        const Colorspace = enum(u32) {
            default = 0, // Default colorspace, i.e. let the driver figure it out. Can only be used with video capture.
            SMPTE170M = 1, // SMPTE 170M: used for broadcast NTSC/PAL SDTV
            SMPTE240M = 2, // Obsolete pre-1998 SMPTE 240M HDTV standard, superseded by Rec 709
            rec709 = 3, // Rec.709: used for HDTV
            // bt878 = 4, // Deprecated, do not use. No driver will ever return this. This was based on a misunderstanding of the bt878 datasheet.
            @"470_system_m" = 5, // NTSC 1953 colorspace. This only makes sense when dealing with really, really old NTSC recordings. Superseded by SMPTE 170M.
            @"470_system_bg" = 6, // EBU Tech 3213 PAL/SECAM colorspace. Effectively shorthand for Colorspace.sRGB, Ycbcr.@"601" and Quantization.full_range. To be used for (Motion-)JPEG.
            jpeg = 7,
            sRGB = 8, // For RGB colorspaces such as produces by most webcams.
            opRGB = 9, // opRGB colorspace
            bt2020 = 10, // BT.2020 colorspace, used for UHDTV.
            raw = 11, // Raw colorspace: for RAW unprocessed images
            dci_p3 = 12, // DCI-P3 colorspace, used by cinema projector

            pub fn mapDefault(kind: enum { sdtv, hdtv, other }) Colorspace {
                return switch (kind) {
                    .sdtv => .SMPTE170M,
                    .hdtv => .rec709,
                    .other => .sRGB,
                };
            }
        };

        const Flags = packed struct(u32) {
            premul_alpha: bool,
            set_csc: bool,

            reserved: u30,
        };

        const Encoding = enum(u32) {
            default = 0,
            @"601" = 1, // ITU-R 601 -- SDTV
            @"709" = 2, // Rec. 709 -- HDTV
            xv601 = 3, // ITU-R 601/EN 61966-2-4 Extended Gamut -- SDTV
            xv709 = 4, // Rec. 709/EN 61966-2-4 Extended Gamut -- HDTV

            // sYCC (Y'CbCr encoding of sRGB), identical to @"601". It was added
            // originally due to a misunderstanding of the sYCC standard. It should
            // not be used, instead use @"601".
            // sYCC = 5,
            bt2020 = 6, // BT.2020 Non-constant Luminance Y'CbCr
            bt2020_const_lum = 7, // BT.2020 Constant Luminance Y'CbcCrc
            SMPTE240M = 8, //SMPTE 240M -- Obsolete HDTV

            hsv180 = 128, // hue mapped to 0-179
            hsv256 = 129, // hue mapped to 0-255

            pub fn mapDefaultYcbcr(c: Colorspace) Encoding {
                return switch (c) {
                    .rec709, .dci_p3 => .@"709",
                    .bt2020 => .bt2020,
                    .SMPTE240M => .SMPTE240M,
                    else => .@"601",
                };
            }
            pub fn category(c: Colorspace) enum { hsv, ycbcr } {
                return if (c == .hsv180 or c == .hsv256) .hsv else .ycbcr;
            }
        };

        const Quantization = enum(u32) {
            default = 0,
            full_range = 1,
            lim_range = 2,

            pub fn mapDefault(c: Colorspace, is_rgb_or_hsv: bool) Quantization {
                return if (is_rgb_or_hsv or c == .jpeg) .full_range else .lim_range;
            }
        };

        const XferFunc = enum(u32) {
            default = 0,
            @"709" = 1,
            sRGB = 2,
            opRGB = 3,
            SMPTE240M = 4,
            none = 5,
            dci_p3 = 6,
            SMPTE2084 = 7,

            // Mapping of XferFunc.default to actual transfer functions for Colorspace
            pub fn mapDefault(c: Colorspace) XferFunc {
                return switch (c) {
                    .SMPTE170M, .@"470_system_m", .@"470_system_bg", .rec709, .bt2020 => .@"709",
                    .sRGB, .jpeg => .sRGB,
                    .opRGB => .opRGB,
                    .SMPTE240M => .SMPTE240M,
                    .raw => .none,
                    .dci_p3 => .dci_p3,
                    .default => unreachable,
                };
            }
        };
    };

    pub const Memory = enum(u32) {
        mmap = 1,
        userptr = 2,
        overlay = 3,
        dmabuf = 4,
    };

    pub const BufferCapabilities = packed struct(u32) {
        mmap: bool,
        userptr: bool,
        dmabuf: bool,
        requests: bool,
        orphaned_bufs: bool,
        m2m_hold_capture_buf: bool,
        mmap_cache_hints: bool,
        max_num_buffers: bool,
        remove_bufs: bool,

        reserved: u23,
    };

    pub const RequestBuffers = extern struct {
        count: u32,
        buf_type: Format.BufType,
        memory: Memory,
        capabilities: BufferCapabilities,
        flags: Flags,

        reserved: [3]u8,

        pub const Flags = packed struct(u8) { non_coherent: bool, reserved: u7 };
    };
    // count is a hint, check returned RequestBuffers.count for actual count
    // if count is 0, free all allocated buffers
    pub fn requestBuffers(f: std.fs.File, bt: Format.BufType, memory: Memory, count: u32) !RequestBuffers {
        std.debug.assert(memory != .overlay);

        var reqbuf = std.mem.zeroes(RequestBuffers);
        reqbuf.buf_type = bt;
        reqbuf.memory = memory;
        reqbuf.count = count;
        ioctl(f, .reqbufs, &reqbuf) catch |err| switch (err) {
            error.Invalid => return error.UnsupportedIOMethod,
            else => return err,
        };

        return reqbuf;
    }

    pub const Buffer = extern struct {
        index: u32,
        buf_type: Format.BufType,
        bytesused: u32, // application sets this if using an output stream
        flags: Flags,
        field: Field, // application sets this if using an output stream
        timestamp: std.os.linux.timeval,
        timecode: Timecode, // valid if flag.timecode is set
        sequence: u32, // frame counter
        memory: Memory,
        m: extern union {
            offset: u32,
            userptr: c_ulong,
            planes: [*]Plane,
            fd: c_int,
        },
        length: u32,
        reserved: u32,
        request_fd: i32,

        pub const Flags = packed struct(u32) {
            mapped: bool, // buffer resides in device memory, and is mapped into application address space
            // if neither queued or done is set, the buffer is 'dequeued'
            queued: bool, // buffer is in incoming queue
            done: bool, // buffer is in outgoing queue
            //  *frame can be set by application if buf_type is an output stream
            keyframe: bool, // i frame,
            pframe: bool,
            bframe: bool,

            corrupted: bool, // this field is called error in c, data in buffer is corrupted
            in_request: bool, // buffer is part of a request that hasn't been queued yet
            timecode: bool, //Buffer.timecode field is valid.. can be set by application if buf_type is an output stream
            m2m_hold_capture_buf: bool,
            prepared: bool, // prepared for io, and can be queued by application
            no_cache_invalidate: bool,
            no_cache_clean: bool,
            timestamp_monotonic: bool, // timestamp taken with CLOCK_MONOTONIC
            timestamp_copy: bool, // capture timestamp taken from output buffer
            _16: u1,
            tstamp_src_soe: bool,
            _18: u3,
            last: bool, // last buffer produced by hardware
            _22: u2,
            request_fd: bool, // request_fd field contains a valid file descriptor
            _24: u8,

            pub fn timestamp(f: Flags) enum { unknown, monotonic, copy } {
                if (f.timestamp_monotonic) return .monotonic;
                return if (f.timestamp_copy) .copy else .unknown;
            }

            pub fn timestampSource(f: Flags) enum { end_of_frame, start_of_exposure } {
                return if (f.tstamp_src_soe) .start_of_exposure else .end_of_frame;
            }
        };
        pub const Plane = extern struct {
            bytesused: u32,
            length: u32,
            m: extern union {
                mem_offset: u32,
                userptr: c_ulong,
                fd: c_int,
            },
            data_offset: u32,
            reserved: [11]u8,
        };
    };

    pub const Timecode = extern struct {
        // empty is invalid, only added to print the struct without errors
        fps: enum(u32) { empty = 0, @"24" = 1, @"25" = 2, @"30" = 3, @"50" = 4, @"60" = 5 },
        flags: Flags,
        frames: u8,
        seconds: u8,
        minutes: u8,
        hours: u8,
        userbits: [4]u8,

        pub const Flags = packed struct(u32) {
            dropframe: bool, // for 29.97 fps material (count frames differently)
            colorframe: bool,
            _3: u1,
            iso8bit: bool,
            _5: u28,

            pub fn userbits(f: Flags) enum { iso8bit, user_defined } {
                return if (f.iso8bit) .iso8bit else .user_defined;
            }
        };
    };

    pub fn queryBuffer(f: std.fs.File, bt: Format.BufType, memory: Memory, index: u32) !Buffer {
        var buf = std.mem.zeroes(Buffer);
        buf.buf_type = bt;
        buf.memory = memory;
        buf.index = index;
        try ioctl(f, .querybuf, &buf);
        return buf;
    }

    pub fn queueBuffer(f: std.fs.File, bt: Format.BufType, memory: Memory, index: u32) !Buffer {
        var buf = std.mem.zeroes(Buffer);
        buf.buf_type = bt;
        buf.memory = memory;
        buf.index = index;
        try ioctl(f, .qbuf, &buf);
        return buf;
    }
    pub fn dequeueBuffer(f: std.fs.File, bt: Format.BufType, memory: Memory) !Buffer {
        var buf = std.mem.zeroes(Buffer);
        buf.buf_type = bt;
        buf.memory = memory;
        buf.index = 0;
        try ioctl(f, .dqbuf, &buf);
        return buf;
    }

    pub fn startStreaming(f: std.fs.File, bt: Format.BufType) !void {
        try ioctl(f, .streamon, @constCast(&bt));
    }
    pub fn stopStreaming(f: std.fs.File, bt: Format.BufType) !void {
        try ioctl(f, .streamoff, @constCast(&bt));
    }
};
