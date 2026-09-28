library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_digilent, nsl_event, nsl_indication, nsl_math,
  nsl_signal_generator, nsl_spdif, nsl_data;
use nsl_math.fixed.all;
use nsl_data.bytestream.all;

-- Stereo test tone over the 4-5 pair of an Ethernet PMOD on J4.
entity boundary is
  port (
    clk_i: in std_ulogic;
    ready_led_o: out std_ulogic;
    done_led_o: out std_ulogic;
    j4_io: inout nsl_digilent.pmod.pmod_double_t
    );
end entity;

architecture arch of boundary is

  constant board_clock_hz_c: natural := 50_000_000;
  constant lock_blink_cycles_c: natural := board_clock_hz_c / 2;
  constant ref_clock_hz_c: natural := 96_000_000;
  constant sample_hz_c: natural := 48_000;
  constant tone_hz_c: natural := 1_000;

  -- 122.88 MHz is exactly 20 times the 6.144 MHz S/PDIF UI rate.
  -- Cascading PLLs realizes it from the board's 50 MHz clock.  GW5A
  -- needs fractional PLL output division at both stages.  The second
  -- output request pins its VCO to 768 MHz, hence an output divisor
  -- of 6.25; 20 output cycles then span exactly 125 VCO cycles.
  constant audio_clock_hz_c: natural := 128 * sample_hz_c * 20;
  constant ui_divisor_c: natural := audio_clock_hz_c / (128 * sample_hz_c);
  constant ref_pll_config_c: nsl_clocking.pll.pll_config_t
    := nsl_clocking.pll.pll_config(
      input_hz => board_clock_hz_c,
      o0 => nsl_clocking.pll.pll_output(ref_clock_hz_c,
                                         allow_fractional => true));
  constant audio_pll_config_c: nsl_clocking.pll.pll_config_t
    := nsl_clocking.pll.pll_config(
      input_hz => ref_clock_hz_c,
      o0 => nsl_clocking.pll.pll_output(audio_clock_hz_c,
                                         allow_fractional => true),
      o1 => nsl_clocking.pll.pll_output(256_000_000,
                                         routing => nsl_clocking.pll_backend.pll_routing_id("NONE")));

  constant phase_step_c: ufixed(-1 downto -32)
    := to_ufixed(real(tone_hz_c) / real(sample_hz_c), -1, -32);
  constant scale_c: sfixed
    := nsl_signal_generator.trigonometry.rect_cordic_init_scaled(0.8, 0, -23);

  -- Consumer, linear PCM, general category, 48 kHz, 24-bit words.
  -- The other 19 status bytes are zero.  Both channels carry the same C
  -- and U blocks; their samples differ by a quarter cycle.
  constant status_c: byte_string(0 to 23)
    := (0 => x"00", 1 => x"00", 2 => x"00", 3 => x"02",
        4 => x"0b", others => x"00");
  constant user_c: byte_string(0 to 23)
    := to_byte_string("NSL SPDIF SINE COS TEST!");

  signal board_clock_s, ref_clock_s, clock_s: std_ulogic;
  signal audio_clocks_s: std_ulogic_vector(0 to audio_pll_config_c.output_count-1);
  signal reset_start_n_s, board_reset_n_s, ref_locked_s, audio_locked_s,
    reset_n_s: std_ulogic;
  signal ref_locked_board_s, audio_locked_board_s: std_ulogic;
  signal ui_tick_s, spdif_s: std_ulogic;
  signal phase_s: ufixed(-1 downto -32);
  signal cordic_ready_s, cordic_valid_s, tx_ready_s: std_ulogic;
  signal cos_s, sin_s: sfixed(0 downto -23);
  signal cos_sample_s, sin_sample_s: unsigned(23 downto 0);

begin

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => board_clock_s
      );

  startup: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => board_clock_s,
      reset_n_o => reset_start_n_s
      );

  board_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => board_clock_s,
      data_i => reset_start_n_s,
      data_o => board_reset_n_s
      );

  ref_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => ref_pll_config_c
      )
    port map(
      clock_i => board_clock_s,
      reset_n_i => board_reset_n_s,
      clock_o(0) => ref_clock_s,
      locked_o => ref_locked_s
      );

  audio_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => audio_pll_config_c
      )
    port map(
      clock_i => ref_clock_s,
      reset_n_i => ref_locked_s,
      clock_o => audio_clocks_s,
      locked_o => audio_locked_s
      );

  -- Monitor each PLL from the board clock, which survives either PLL
  -- losing lock.  The samplers assert low asynchronously and release
  -- after two 50 MHz edges, making short unlocks visible to the
  -- activity monitors' own two-sample deglitchers.
  ref_lock_sampler: nsl_clocking.async.async_edge
    port map(
      clock_i => board_clock_s,
      data_i => ref_locked_s,
      data_o => ref_locked_board_s
      );

  audio_lock_sampler: nsl_clocking.async.async_edge
    port map(
      clock_i => board_clock_s,
      data_i => audio_locked_s,
      data_o => audio_locked_board_s
      );

  ref_lock_activity: nsl_indication.activity.activity_monitor
    generic map(
      blink_cycles_c => lock_blink_cycles_c
      )
    port map(
      clock_i => board_clock_s,
      reset_n_i => board_reset_n_s,
      togglable_i => ref_locked_board_s,
      activity_o => ready_led_o
      );

  audio_lock_activity: nsl_indication.activity.activity_monitor
    generic map(
      blink_cycles_c => lock_blink_cycles_c
      )
    port map(
      clock_i => board_clock_s,
      reset_n_i => board_reset_n_s,
      togglable_i => audio_locked_board_s,
      activity_o => done_led_o
      );

  clock_s <= audio_clocks_s(0);

  audio_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_s,
      data_i => audio_locked_s,
      data_o => reset_n_s
      );

  -- One tick every 20 PLL cycles, with no variable-length UI periods.
  ui_clock: nsl_event.tick.tick_generator_integer
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      period_m1_i => to_unsigned(ui_divisor_c - 1, 5),
      tick_o => ui_tick_s
      );

  -- The CORDIC keeps its result until the transmitter takes the whole
  -- stereo frame.  Only then does the next phase enter the CORDIC.
  phase_accumulator: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if cordic_ready_s = '1' then
        phase_s <= phase_s + phase_step_c;
      end if;
    end if;

    if reset_n_s = '0' then
      phase_s <= (others => '0');
    end if;
  end process;

  oscillator: nsl_signal_generator.trigonometry.rect_cordic_scaled
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      scale_i => scale_c,
      angle_i => phase_s,
      ready_o => cordic_ready_s,
      valid_i => '1',
      x_o => cos_s,
      y_o => sin_s,
      valid_o => cordic_valid_s,
      ready_i => tx_ready_s
      );

  sin_sample_s <= to_unsigned(sin_s);
  cos_sample_s <= to_unsigned(cos_s);

  transmitter: nsl_spdif.transceiver.spdif_tx
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      ui_tick_i => ui_tick_s,
      block_ready_o => open,
      block_user_i => user_c,
      block_channel_status_i => status_c,
      ready_o => tx_ready_s,
      valid_i => cordic_valid_s,
      a_i.aux => sin_sample_s(3 downto 0),
      a_i.audio => sin_sample_s(23 downto 4),
      a_i.valid => '1',
      b_i.aux => cos_sample_s(3 downto 0),
      b_i.audio => cos_sample_s(23 downto 4),
      b_i.valid => '1',
      spdif_o => spdif_s
      );

  -- The Ethernet PMOD's RJ45 contacts 4/5 connect to PMOD pins 2/6.
  -- Drive those two FPGA pins in opposite phase.  The other three
  -- transformer pairs are released and biased by the pull settings.
  j4_io(2) <= std_logic(spdif_s);
  j4_io(6) <= std_logic(not spdif_s);
  j4_io(1) <= 'Z';
  j4_io(3) <= 'Z';
  j4_io(4) <= 'Z';
  j4_io(5) <= 'Z';
  j4_io(7) <= 'Z';
  j4_io(8) <= 'Z';

end architecture;
