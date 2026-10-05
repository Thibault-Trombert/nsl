library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_synthesis;
use nsl_video.pixel_stream.all;

entity color_bars is
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
end color_bars;

architecture beh of color_bars is

  subtype index_t is unsigned(config_c.component_bits-1 downto 0);

  type regs_t is
  record
    index: index_t;
    bar_left: natural range 0 to bar_width_c - 1;
  end record;

  signal r, rin: regs_t;

  signal x_s: unsigned(nsl_video.mode.x_width(geometry_c)-1 downto 0);
  signal taken_s: std_ulogic;
  signal pixel_s: pixel_vector(0 to config_c.pixel_count-1);

begin

  bar_width_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A bar spans at least two pixels",
      condition_c => bar_width_c >= 2
      )
    port map(
      unused_i => '0'
      );

  one_pixel_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Bars are stated one pixel at a time",
      condition_c => config_c.pixel_count = 1
      )
    port map(
      unused_i => '0'
      );

  indexed_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Bars are stated as palette indices",
      condition_c => config_c.colorspace = COLORSPACE_INDEXED
      )
    port map(
      unused_i => '0'
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.index <= (others => '0');
      r.bar_left <= bar_width_c - 1;
    end if;
  end process;

  transition: process(r, x_s, taken_s) is
  begin
    rin <= r;

    if taken_s = '1' then
      -- Bars start over on every line, so taking the first pixel of
      -- one leaves the first bar one pixel short whatever the state
      -- the previous line ended in.
      if x_s = 0 then
        rin.index <= (others => '0');
        rin.bar_left <= bar_width_c - 2;
      elsif r.bar_left /= 0 then
        rin.bar_left <= r.bar_left - 1;
      else
        rin.bar_left <= bar_width_c - 1;
        rin.index <= r.index + 1;
      end if;
    end if;
  end process;

  mealy: process(r, x_s) is
    variable p: pixel_t;
  begin
    p := pixel_zero_c;
    if x_s /= 0 then
      p(0) := resize(r.index, max_component_bits_c);
    end if;
    pixel_s(0) <= p;
  end process;

  framer: nsl_video.raster.pixel_stream_framer
    generic map(
      geometry_c => geometry_c,
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      enable_i => enable_i,
      x_o => x_s,
      y_o => open,
      pixel_i => pixel_s,
      taken_o => taken_s,
      out_o => out_o,
      out_i => out_i
      );

end beh;
