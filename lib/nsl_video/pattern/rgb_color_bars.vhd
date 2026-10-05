library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video;

entity rgb_color_bars is
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
end rgb_color_bars;

architecture beh of rgb_color_bars is

  constant index_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 1, components => 1, component_bits => 3);
  constant palette_c : nsl_video.pixel_stream.pixel_vector(0 to 7)
    := nsl_video.pixel_stream.palette(config_c, nsl_video.pattern.color_bars_palette_c);

  signal index_s: nsl_video.pixel_stream.bus_t;

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
      out_config_c => config_c
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
