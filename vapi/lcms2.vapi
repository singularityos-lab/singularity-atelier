[CCode (cheader_filename = "lcms2.h")]
namespace Lcms {
    [Compact]
    [CCode (cname = "void", free_function = "cmsCloseProfile")]
    public class Profile {
        [CCode (cname = "cmsCreate_sRGBProfile")]
        public Profile.srgb ();
        [CCode (cname = "cmsCreateLab4Profile")]
        public Profile.lab4 (void* white_point = null);
        [CCode (cname = "cmsOpenProfileFromFile")]
        public Profile.from_file (string path, string mode = "r");
        [CCode (cname = "cmsOpenProfileFromMem")]
        public Profile.from_memory (uint8[] data);
        [CCode (cname = "cmsGetColorSpace")]
        public uint32 color_space ();
    }

    [Compact]
    [CCode (cname = "void", free_function = "cmsDeleteTransform")]
    public class Transform {
        [CCode (cname = "cmsCreateTransform")]
        public Transform (Profile input, uint32 in_format, Profile output, uint32 out_format, uint32 intent, uint32 flags);
        [CCode (cname = "cmsCreateProofingTransform")]
        public Transform.proofing (Profile input, uint32 in_format, Profile output, uint32 out_format, Profile proofing, uint32 intent, uint32 proofing_intent, uint32 flags);
        [CCode (cname = "cmsDoTransform")]
        public void apply (void* input, void* output, uint32 size);
    }

    [CCode (cname = "TYPE_RGB_DBL")]
    public const uint32 TYPE_RGB_DBL;
    [CCode (cname = "TYPE_Lab_DBL")]
    public const uint32 TYPE_LAB_DBL;
    [CCode (cname = "TYPE_CMYK_DBL")]
    public const uint32 TYPE_CMYK_DBL;
    [CCode (cname = "INTENT_PERCEPTUAL")]
    public const uint32 INTENT_PERCEPTUAL;
    [CCode (cname = "INTENT_RELATIVE_COLORIMETRIC")]
    public const uint32 INTENT_RELATIVE_COLORIMETRIC;
    [CCode (cname = "cmsFLAGS_SOFTPROOFING")]
    public const uint32 FLAGS_SOFTPROOFING;
    [CCode (cname = "cmsFLAGS_GAMUTCHECK")]
    public const uint32 FLAGS_GAMUTCHECK;
    [CCode (cname = "cmsSigCmykData")]
    public const uint32 SIG_CMYK;
}
