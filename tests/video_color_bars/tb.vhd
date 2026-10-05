library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_color;
use nsl_video.pixel_stream.all;
use nsl_color.rgb.all;

-- Runs color_bars, optionally through a palette_expander fed with
-- color_bars_palette_c, under downstream stalls, and checks every
-- beat of a few frames against the bar its position falls in, and
-- against its framing.
entity bars_check is
  generic(
    index_bits_c : natural;
    bar_width_c : natural;
    width_c : natural;
    height_c : natural;
    -- INDEXED for raw indices, a color configuration for an expanded
    -- stream.
    out_config_c : config_t;
    stall_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    done_o : out boolean
    );
end entity;

architecture sim of bars_check is

  constant geometry_c : nsl_video.mode.geometry_t
    := nsl_video.mode.geometry(width_c, height_c);
  constant index_config_c : config_t
    := config(components => 1, component_bits => index_bits_c);
  constant expanded_c : boolean := out_config_c.colorspace /= COLORSPACE_INDEXED;

  constant frame_count_c : natural := 3;
  constant beat_count_c : natural := width_c * height_c * frame_count_c;

  -- Classic bars, left to right.
  constant bars_c : rgb24_vector(0 to 7) := (
    (x"00", x"00", x"00"),
    (x"00", x"00", x"ff"),
    (x"00", x"80", x"00"),
    (x"00", x"ff", x"ff"),
    (x"ff", x"00", x"00"),
    (x"ff", x"00", x"ff"),
    (x"ff", x"ff", x"00"),
    (x"ff", x"ff", x"ff"));

  signal out_s : bus_t;

  function expected(x: natural) return pixel_t is
    constant index: natural := (x / bar_width_c) mod 2 ** index_bits_c;
    variable ret: pixel_t := pixel_zero_c;
  begin
    if expanded_c then
      ret := color(out_config_c, bars_c(index));
      for c in out_config_c.component_count to max_component_count_c - 1 loop
        ret(c) := (others => '0');
      end loop;
    else
      ret(0) := to_unsigned(index, max_component_bits_c);
    end if;
    return ret;
  end function;

begin

  raw: if not expanded_c
  generate
    dut: nsl_video.pattern.color_bars
      generic map(
        geometry_c => geometry_c,
        config_c => index_config_c,
        bar_width_c => bar_width_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        out_o => out_s.m,
        out_i => out_s.s
        );
  end generate;

  expanded: if expanded_c
  generate
    signal index_s : bus_t;
  begin
    dut: nsl_video.pattern.color_bars
      generic map(
        geometry_c => geometry_c,
        config_c => index_config_c,
        bar_width_c => bar_width_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
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
        palette_i => palette(out_config_c, nsl_video.pattern.color_bars_palette_c),
        in_i => index_s.m,
        in_o => index_s.s,
        out_o => out_s.m,
        out_i => out_s.s
        );
  end generate;

  sink: process is
    variable x, y: natural;
  begin
    done_o <= false;
    out_s.s <= accept(out_config_c, ready => false);
    wait until reset_n_i = '1';

    for i in 0 to beat_count_c - 1 loop
      wait until falling_edge(clock_i);
      for k in 1 to i mod stall_c loop
        wait until falling_edge(clock_i);
      end loop;
      out_s.s <= accept(out_config_c, ready => true);
      wait until rising_edge(clock_i) and is_valid(out_config_c, out_s.m);

      x := i mod width_c;
      y := (i / width_c) mod height_c;
      assert pixel(out_config_c, out_s.m) = expected(x)
        report sink'path_name & "beat " & integer'image(i) & " at x " & integer'image(x)
        & ": bad pixel"
        severity failure;
      assert is_sof(out_config_c, out_s.m) = (x = 0 and y = 0)
        and is_last(out_config_c, out_s.m) = (x = width_c - 1)
        and (x /= width_c - 1
             or is_eof(out_config_c, out_s.m) = (y = height_c - 1))
        report sink'path_name & "beat " & integer'image(i) & ": bad framing"
        severity failure;

      wait until falling_edge(clock_i);
      out_s.s <= accept(out_config_c, ready => false);
    end loop;

    done_o <= true;
    wait;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;

library nsl_video, nsl_simulation;
use nsl_video.pixel_stream.all;

entity tb is
end entity;

architecture sim of tb is

  constant clock_period_c : time := 10 ns;

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;
  type done_vector is array(natural range <>) of boolean;
  signal done_s : done_vector(0 to 3);

begin

  clock_s <= not clock_s after clock_period_c / 2 when done_s /= (done_s'range => true) else '0';

  reset_gen: process is
  begin
    reset_n_s <= '0';
    wait for 4 * clock_period_c;
    reset_n_s <= '1';
    wait;
  end process;

  -- Ten bars a line, and a line width that is not a bar multiple:
  -- indices wrap and the last bar is cut.
  rgb: entity work.bars_check
    generic map(
      index_bits_c => 3,
      bar_width_c => 3,
      width_c => 29,
      height_c => 3,
      out_config_c => config(pixels => 1),
      stall_c => 3
      )
    port map(clock_i => clock_s, reset_n_i => reset_n_s, done_o => done_s(0));

  rgb_full_rate: entity work.bars_check
    generic map(
      index_bits_c => 3,
      bar_width_c => 2,
      width_c => 20,
      height_c => 2,
      out_config_c => config(pixels => 1),
      stall_c => 1
      )
    port map(clock_i => clock_s, reset_n_i => reset_n_s, done_o => done_s(1));

  ycbcr: entity work.bars_check
    generic map(
      index_bits_c => 3,
      bar_width_c => 4,
      width_c => 32,
      height_c => 2,
      out_config_c => config(colorspace => COLORSPACE_YCBCR444),
      stall_c => 2
      )
    port map(clock_i => clock_s, reset_n_i => reset_n_s, done_o => done_s(2));

  -- Four-bit indices wrap after sixteen bars.
  raw: entity work.bars_check
    generic map(
      index_bits_c => 4,
      bar_width_c => 2,
      width_c => 40,
      height_c => 2,
      out_config_c => config(components => 1, component_bits => 4),
      stall_c => 2
      )
    port map(clock_i => clock_s, reset_n_i => reset_n_s, done_o => done_s(3));

  finish: process is
  begin
    wait until done_s = (done_s'range => true);
    nsl_simulation.control.terminate(0);
    wait;
  end process;

  watchdog: process is
  begin
    wait for 1 ms;
    assert false report "Timeout" severity failure;
  end process;

end architecture;
