// C ABI of studio-photo-engine (Rust, over LightCraft). See src/lib.rs for the ownership rules.
#ifndef STUDIO_PHOTO_ENGINE_H
#define STUDIO_PHOTO_ENGINE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ScPhoto ScPhoto;

typedef struct ScImage {
    uint32_t width;
    uint32_t height;
    /// RGBA8, not premultiplied, stride = width * 4.
    uint8_t *data;
    size_t len;
} ScImage;

/// Opens a raw or rendered image; decodes a preview whose long edge is at most `preview_edge`.
/// Returns NULL and sets `*err` (free with sc_string_free) on failure.
ScPhoto *sc_photo_open(const char *path, uint32_t preview_edge, char **err);
void sc_photo_free(ScPhoto *photo);

/// JSON: {rawFormat, rawSupported, isRaw, asShotTemp, asShotTint, relativeWB, previewWidth, previewHeight, fullWidth, fullHeight}
char *sc_photo_info_json(const ScPhoto *photo);
/// Full DevelopSettings JSON the engine starts this photo with.
char *sc_photo_default_settings_json(const ScPhoto *photo);

/// Renders the preview with `settings_json` into an RGBA8 image fitting max_w x max_h. Free with sc_image_free.
ScImage *sc_photo_render(ScPhoto *photo, const char *settings_json, uint32_t max_w, uint32_t max_h, bool draft, char **err);
void sc_image_free(ScImage *image);

/// Automatic tone ("Auto") for the photo under settings_json: JSON {"light":{...},"color":{...},"bw_mix":{...}}
/// with develop-settings paths. Free with sc_string_free; null with *err set on failure.
char *sc_photo_auto_json(ScPhoto *photo, const char *settings_json, char **err);

/// Exports the full-resolution original. format: jpg|png|tif|webp|avif|dng. long_edge 0 = full size.
/// Returns JSON {width, height, bytes} or NULL with *err set.
char *sc_photo_export(ScPhoto *photo, const char *settings_json, const char *out_path, const char *format,
                      uint8_t quality, uint32_t long_edge, char **err);

/// Full-resolution (or long_edge-fitted) render of the original, tile by tile (tile 0 = 1024 px).
/// Lower peak memory than sc_photo_export; the caller encodes the RGBA8 result. Free with sc_image_free.
ScImage *sc_photo_render_tiled(ScPhoto *photo, const char *settings_json, uint32_t long_edge, uint32_t tile, char **err);

/// JSON {format, supported, headerReadable}; format is null when the file is not a recognised raw.
char *sc_raw_probe(const char *path, char **err);

void sc_string_free(char *s);
char *sc_engine_version(void);

#ifdef __cplusplus
}
#endif
#endif
