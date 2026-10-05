library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_video;

package colormap is

  -- Turns a colour-index pixel stream into a colour one, one entry
  -- of the palette per pixel.
  --
  -- Index width comes from the input configuration, which states one
  -- component: a stream of eight-bit indices looks up a palette of
  -- 256 entries.  The lookup is registered, and framing travels with
  -- the pixel it belongs to.
  --
  -- This is palette_expander with an RGB palette, for RGB outputs.
  component colormap_lookup is
    generic(
      in_config_c : nsl_video.pixel_stream.config_t;
      out_config_c : nsl_video.pixel_stream.config_t
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      palette_i : nsl_color.rgb.rgb24_vector(0 to 2**in_config_c.component_bits-1);

      in_i : in nsl_video.pixel_stream.master_t;
      in_o : out nsl_video.pixel_stream.slave_t;

      out_o : out nsl_video.pixel_stream.master_t;
      out_i : in nsl_video.pixel_stream.slave_t
      );
  end component;

  -- Turns an indexed pixel stream into a colour one, one entry of
  -- the palette per pixel.
  --
  -- Input configuration is INDEXED, its component width tells the
  -- palette size.  Output configuration is any colorspace that shows
  -- colours, palette entries are pixels in that configuration, as
  -- nsl_video.pixel_stream.palette() computes them from RGB
  -- constants.  For a YCBCR422 output, entries hold Y, Cb and Cr,
  -- and each pixel takes the chroma its position in the line calls
  -- for, Cb first.
  --
  -- Palette is a port: tying it to a constant folds the lookup into
  -- logic, driving it allows changing colors at run time.  The
  -- lookup is registered, a beat takes one cycle to go through, and
  -- a full rate stream goes through without bubbles.  Framing
  -- travels with the pixel it belongs to.
  component palette_expander is
    generic(
      in_config_c : nsl_video.pixel_stream.config_t;
      out_config_c : nsl_video.pixel_stream.config_t
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      palette_i : in nsl_video.pixel_stream.pixel_vector(0 to 2**in_config_c.component_bits-1);

      in_i : in nsl_video.pixel_stream.master_t;
      in_o : out nsl_video.pixel_stream.slave_t;

      out_o : out nsl_video.pixel_stream.master_t;
      out_i : in nsl_video.pixel_stream.slave_t
      );
  end component;

end package;
