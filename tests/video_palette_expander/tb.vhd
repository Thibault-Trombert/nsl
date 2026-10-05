library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_color;
use nsl_video.pixel_stream.all;
use nsl_color.rgb.all;

-- Pushes framed lines of indices through a palette_expander, with
-- stalls on both sides, and checks every output beat against the
-- palette color of its index, its framing, and for a 4:2:2 output,
-- the chroma its position in the line takes.
entity expander_check is
  generic(
    out_config_c : config_t;
    in_stall_c : natural;
    out_stall_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    done_o : out boolean
    );
end entity;

architecture sim of expander_check is

  constant in_config_c : config_t := config(components => 1, component_bits => 2);

  constant colors_c : rgb24_vector(0 to 3) := (
    rgb24_black, rgb24_red, rgb24_lime, rgb24_white);
  constant palette_c : pixel_vector(0 to 3) := palette(out_config_c, colors_c);

  constant width_c : natural := 6;
  constant height_c : natural := 3;
  constant frame_count_c : natural := 2;
  constant beat_count_c : natural := width_c * height_c * frame_count_c;

  signal in_s, out_s : bus_t;

  function index_of(i: natural) return natural is
  begin
    return (i * 5 + i / 7 + 3) mod 4;
  end function;

  function expected(i: natural) return pixel_t is
    variable ret: pixel_t := palette_c(index_of(i));
  begin
    if out_config_c.colorspace = COLORSPACE_YCBCR422 then
      if (i mod width_c) mod 2 = 1 then
        ret(1) := ret(2);
      end if;
    end if;
    for c in out_config_c.component_count to max_component_count_c - 1 loop
      ret(c) := (others => '0');
    end loop;
    return ret;
  end function;

begin

  dut: nsl_video.colormap.palette_expander
    generic map(
      in_config_c => in_config_c,
      out_config_c => out_config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      palette_i => palette_c,
      in_i => in_s.m,
      in_o => in_s.s,
      out_o => out_s.m,
      out_i => out_s.s
      );

  source: process is
    variable p: pixel_t;
    variable x, y: natural;
  begin
    in_s.m <= transfer(in_config_c, pixel_zero_c, valid => false);
    wait until reset_n_i = '1';
    wait until falling_edge(clock_i);

    for i in 0 to beat_count_c - 1 loop
      for k in 1 to i mod in_stall_c loop
        wait until falling_edge(clock_i);
      end loop;
      x := i mod width_c;
      y := (i / width_c) mod height_c;
      p := pixel_zero_c;
      p(0) := to_unsigned(index_of(i), max_component_bits_c);
      in_s.m <= transfer(in_config_c, p,
                         sof => x = 0 and y = 0,
                         last => x = width_c - 1,
                         eof => x = width_c - 1 and y = height_c - 1);
      wait until rising_edge(clock_i) and is_ready(in_config_c, in_s.s);
      wait until falling_edge(clock_i);
      in_s.m <= transfer(in_config_c, pixel_zero_c, valid => false);
    end loop;
    wait;
  end process;

  sink: process is
    variable x, y: natural;
  begin
    done_o <= false;
    out_s.s <= accept(out_config_c, ready => false);
    wait until reset_n_i = '1';

    for i in 0 to beat_count_c - 1 loop
      wait until falling_edge(clock_i);
      for k in 1 to i mod out_stall_c loop
        wait until falling_edge(clock_i);
      end loop;
      out_s.s <= accept(out_config_c, ready => true);
      wait until rising_edge(clock_i) and is_valid(out_config_c, out_s.m);

      x := i mod width_c;
      y := (i / width_c) mod height_c;
      assert pixel(out_config_c, out_s.m) = expected(i)
        report "Beat " & integer'image(i) & ": bad pixel"
        severity failure;
      assert is_sof(out_config_c, out_s.m) = (x = 0 and y = 0)
        and is_last(out_config_c, out_s.m) = (x = width_c - 1)
        and (x /= width_c - 1
             or is_eof(out_config_c, out_s.m) = (y = height_c - 1))
        report "Beat " & integer'image(i) & ": bad framing"
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

  rgb: entity work.expander_check
    generic map(
      out_config_c => config(pixels => 1),
      in_stall_c => 3,
      out_stall_c => 2
      )
    port map(clock_i => clock_s, reset_n_i => reset_n_s, done_o => done_s(0));

  ycbcr422: entity work.expander_check
    generic map(
      out_config_c => config(colorspace => COLORSPACE_YCBCR422),
      in_stall_c => 2,
      out_stall_c => 5
      )
    port map(clock_i => clock_s, reset_n_i => reset_n_s, done_o => done_s(1));

  bw: entity work.expander_check
    generic map(
      out_config_c => config(colorspace => COLORSPACE_GRAY, component_bits => 1),
      in_stall_c => 1,
      out_stall_c => 1
      )
    port map(clock_i => clock_s, reset_n_i => reset_n_s, done_o => done_s(2));

  ycbcr422_full_rate: entity work.expander_check
    generic map(
      out_config_c => config(colorspace => COLORSPACE_YCBCR422),
      in_stall_c => 1,
      out_stall_c => 1
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
