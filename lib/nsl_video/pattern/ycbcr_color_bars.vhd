library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_video;
use nsl_video.pixel_stream.all;

entity ycbcr_color_bars is
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
end ycbcr_color_bars;

architecture beh of ycbcr_color_bars is

  function ycbcr_view(cfg: config_t) return config_t
  is
    variable ret: config_t := cfg;
  begin
    if cfg.colorspace = COLORSPACE_YCBCR444 or cfg.colorspace = COLORSPACE_YCBCR422 then
      return cfg;
    end if;

    assert cfg.component_count = 3
      report "YCbCr bars take three components"
      severity failure;

    ret.colorspace := COLORSPACE_YCBCR444;
    ret.colorimetry := COLORIMETRY_BT709;
    ret.quantization := QUANTIZATION_LIMITED;
    return ret;
  end function;

  -- White bar first
  function rotated(colors: nsl_color.rgb.rgb24_vector) return nsl_color.rgb.rgb24_vector
  is
    alias xcolors: nsl_color.rgb.rgb24_vector(0 to colors'length-1) is colors;
    variable ret: nsl_color.rgb.rgb24_vector(0 to colors'length-1);
  begin
    for i in ret'range
    loop
      ret(i) := xcolors((i + colors'length - 1) mod colors'length);
    end loop;
    return ret;
  end function;

  constant index_config_c : config_t
    := config(pixels => 1, components => 1, component_bits => 3);
  constant out_config_c : config_t := ycbcr_view(config_c);
  constant palette_c : pixel_vector(0 to 7)
    := palette(out_config_c, rotated(nsl_video.pattern.color_bars_palette_c));

  signal index_s: bus_t;

begin

  assert false
    report "This component is deprecated, move to nsl_video.pattern.color_bars and nsl_video.colormap.palette_expander"
    severity warning;

  bars: nsl_video.pattern.color_bars
    generic map(
      geometry_c => geometry_c,
      config_c => index_config_c,
      bar_width_c => bar_width_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      enable_i => enable_i,
      out_o => index_s.m,
      out_i => index_s.s
      );

  expander: nsl_video.colormap.palette_expander
    generic map(
      in_config_c => index_config_c,
      out_config_c => out_config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      palette_i => palette_c,
      in_i => index_s.m,
      in_o => index_s.s,
      out_o => out_o,
      out_i => out_i
      );

end beh;
