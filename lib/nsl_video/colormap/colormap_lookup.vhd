library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_video;
use nsl_video.pixel_stream.all;

entity colormap_lookup is
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
end entity;

architecture beh of colormap_lookup is

  signal palette_s: pixel_vector(palette_i'range);

begin

  convert: for i in palette_i'range
  generate
    palette_s(i) <= to_pixel(out_config_c, palette_i(i));
  end generate;

  expander: nsl_video.colormap.palette_expander
    generic map(
      in_config_c => in_config_c,
      out_config_c => out_config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      palette_i => palette_s,
      in_i => in_i,
      in_o => in_o,
      out_o => out_o,
      out_i => out_i
      );

end architecture;
