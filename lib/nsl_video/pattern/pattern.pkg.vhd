library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_video;

-- Test patterns.
--
-- A pattern says nothing about what carries it: the same bars go out
-- over DVI, over HDMI, to a panel or to a file.  What differs between
-- these two is the colourspace they state a pixel in, which is a
-- property of the stream rather than of the link -- a link simply
-- sends what it is given, and what a sink asked for is settled long
-- before, in its EDID.
package pattern is

  -- Colors of the classic eight bars, in the order color_bars shows
  -- them with three-bit indices.
  constant color_bars_palette_c : nsl_color.rgb.rgb24_vector(0 to 7) := (
    nsl_color.rgb.rgb24_black,
    nsl_color.rgb.rgb24_blue,
    nsl_color.rgb.rgb24_green,
    nsl_color.rgb.rgb24_cyan,
    nsl_color.rgb.rgb24_red,
    nsl_color.rgb.rgb24_magenta,
    nsl_color.rgb.rgb24_yellow,
    nsl_color.rgb.rgb24_white
    );

  -- Vertical bars of palette indices.
  --
  -- config_c is INDEXED, one pixel per beat.  Bar k, counted from
  -- the left of the line, shows index k modulo 2**component_bits.
  -- Bars restart on every line, so the first one is a whole bar wide
  -- whatever the line width is.
  --
  -- Through nsl_video.colormap.palette_expander with a palette
  -- computed from color_bars_palette_c, three-bit indices show the
  -- classic bars in any colorspace.
  component color_bars is
    generic(
      geometry_c : nsl_video.mode.geometry_t;
      config_c : nsl_video.pixel_stream.config_t;
      bar_width_c : natural := 128
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';

      out_o : out nsl_video.pixel_stream.master_t;
      out_i : in nsl_video.pixel_stream.slave_t
      );
  end component;

  -- Eight bars of RGB, color_bars_palette_c in order.
  --
  -- Bars restart on every line, so the first one is a whole bar wide
  -- whatever the line width is.
  --
  -- Deprecated: use color_bars and nsl_video.colormap.palette_expander
  -- with a palette computed from color_bars_palette_c.
  component rgb_color_bars is
    generic(
      geometry_c : nsl_video.mode.geometry_t;
      config_c : nsl_video.pixel_stream.config_t;
      bar_width_c : natural := 128
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';

      out_o : out nsl_video.pixel_stream.master_t;
      out_i : in nsl_video.pixel_stream.slave_t
      );
  end component;

  -- The same bars, stated in YCbCr, white bar first.  The stream
  -- carries luma first, as the colourspace names it, which is the
  -- order nsl_dvi.encoder.channel_map_ycbcr_c expects.  Unless
  -- config_c states a YCbCr colorspace, bars are BT.709 limited
  -- range, chroma in offset binary, laid out as config_c says.
  --
  -- Deprecated: use color_bars and nsl_video.colormap.palette_expander
  -- with a palette computed from color_bars_palette_c.
  component ycbcr_color_bars is
    generic(
      geometry_c : nsl_video.mode.geometry_t;
      config_c : nsl_video.pixel_stream.config_t;
      bar_width_c : natural := 128
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';

      out_o : out nsl_video.pixel_stream.master_t;
      out_i : in nsl_video.pixel_stream.slave_t
      );
  end component;

end package;
