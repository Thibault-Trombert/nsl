library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_adi, nsl_i2c, nsl_bnoc, nsl_video, nsl_data, nsl_simulation;
use nsl_adi.adv7511.all;
use nsl_video.pixel_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;

-- Control side: drives the ADV7511 driver through a real I2C
-- transactor against a model of the chip register map.  The model
-- keeps hot plug status, sets the hot plug interrupt on every
-- transition, and forgets its configuration when the sink goes away,
-- as the chip does.  Configuration must be complete after the sink
-- appears, and again after it goes away and comes back.
--
-- Video side: runs a small raster from a 4:2:2 stream and checks
-- syncs, data enable and the chroma/luma bus layout.
entity tb is
end entity;

architecture sim of tb is

  -- Control domain
  constant clock_hz_c : natural := 16_000_000;
  constant clock_period_c : time := 1 sec / clock_hz_c;
  constant scl_hz_c : natural := 400_000;
  constant i2c_divisor_c : unsigned(4 downto 0)
    := nsl_i2c.transactor.scl_divisor(clock_hz_c, scl_hz_c);
  -- Transactor counts eight cycles per half SCL period at divisor 0
  -- at this clock rate
  constant scl_period_c : time := 2 * 8 * (to_integer(i2c_divisor_c) + 1) * clock_period_c;
  -- Shortens startup and poll delays to a few thousand cycles
  constant driver_clock_hz_c : natural := 40_000;
  constant saddr_c : unsigned(7 downto 1) := i2c_saddr_default_c;

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;
  signal done_s : boolean := false;

  signal cmd_s, rsp_s : nsl_bnoc.framed.framed_bus;
  signal i2c_s : nsl_i2c.i2c.i2c_i;
  signal i2c_o_s : nsl_i2c.i2c.i2c_o_vector(0 to 1);

  signal mem_addr_s : unsigned(7 downto 0);
  signal mem_r_data_s, mem_w_data_s : std_ulogic_vector(7 downto 0);
  signal mem_w_valid_s : std_ulogic;

  type reg_file_t is array(0 to 255) of byte;
  signal regs_s : reg_file_t := (others => x"00");
  signal hpd_s : std_ulogic := '0';
  signal hpd_irq_s : std_ulogic := '0';
  signal irq_n_s : std_ulogic;

  signal hpd_out_s, ready_s : std_ulogic;
  signal scl_shortest_s : time;

  -- Video domain
  constant pixel_period_c : time := 10 ns;
  constant h_act_c : natural := 8;
  constant v_act_c : natural := 4;
  constant config_c : config_t := config(colorspace => COLORSPACE_YCBCR422);

  signal pixel_clock_s : std_ulogic := '0';
  signal pixel_reset_n_s : std_ulogic;
  signal pixel_s : bus_t;
  signal synced_s : std_ulogic;
  signal hd_clock_s, hd_de_s, hd_hsync_s, hd_vsync_s : std_ulogic;
  signal hd_data_s : std_ulogic_vector(15 downto 0);
  signal video_done_s : boolean := false;

  function luma(x, y: natural) return natural is
  begin
    return 16 + x * 16 + y;
  end function;

  function chroma(x, y: natural) return natural is
  begin
    return 128 + x * 8 + y;
  end function;

begin

  clock_s <= not clock_s after clock_period_c / 2 when not done_s else '0';
  pixel_clock_s <= not pixel_clock_s after pixel_period_c / 2 when not video_done_s else '0';

  reset_gen: process is
  begin
    reset_n_s <= '0';
    pixel_reset_n_s <= '0';
    wait for 10 * clock_period_c;
    reset_n_s <= '1';
    pixel_reset_n_s <= '1';
    wait;
  end process;

  dut: nsl_adi.adv7511.adv7511_driver
    generic map(
      clock_i_hz_c => driver_clock_hz_c,
      config_c => config_c,
      i2c_saddr_c => saddr_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      irq_n_i => irq_n_s,

      i2c_divisor_i => i2c_divisor_c,
      cmd_o => cmd_s.req,
      cmd_i => cmd_s.ack,
      rsp_i => rsp_s.req,
      rsp_o => rsp_s.ack,

      aspect_i => ASPECT_16_9,
      hdmi_i => '1',
      audio_enable_i => '1',
      audio_rate_i => AUDIO_RATE_48K,

      hpd_o => hpd_out_s,
      ready_o => ready_s,

      pixel_clock_i => pixel_clock_s,
      pixel_reset_n_i => pixel_reset_n_s,

      v_fp_m1_i => to_unsigned(0, 4),
      v_sync_m1_i => to_unsigned(1, 4),
      v_bp_m1_i => to_unsigned(0, 4),
      v_act_m1_i => to_unsigned(v_act_c - 1, 4),
      h_fp_m1_i => to_unsigned(1, 5),
      h_sync_m1_i => to_unsigned(2, 5),
      h_bp_m1_i => to_unsigned(1, 5),
      h_act_m1_i => to_unsigned(h_act_c - 1, 5),
      vsync_i => '1',
      hsync_i => '0',

      pixel_i => pixel_s.m,
      pixel_o => pixel_s.s,
      synced_o => synced_s,

      clock_o => hd_clock_s,
      de_o => hd_de_s,
      hsync_o => hd_hsync_s,
      vsync_o => hd_vsync_s,
      data_o => hd_data_s
      );

  transactor: nsl_i2c.transactor.transactor_framed_controller
    generic map(
      clock_i_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      i2c_o => i2c_o_s(0),
      i2c_i => i2c_s,
      cmd_i => cmd_s.req,
      cmd_o => cmd_s.ack,
      rsp_o => rsp_s.req,
      rsp_i => rsp_s.ack
      );

  resolver: nsl_i2c.i2c.i2c_resolver
    generic map(
      port_count => 2
      )
    port map(
      bus_i => i2c_o_s,
      bus_o => i2c_s
      );

  chip_i2c: nsl_i2c.clocked.clocked_memory_controller
    generic map(
      addr_bytes => 1,
      data_bytes => 1
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      slave_address_i => saddr_c,
      i2c_o => i2c_o_s(1),
      i2c_i => i2c_s,
      addr_o => mem_addr_s,
      r_data_i => mem_r_data_s,
      w_valid_o => mem_w_valid_s,
      w_data_o => mem_w_data_s
      );

  -- Register map model
  chip_read: process(mem_addr_s, regs_s, hpd_s, hpd_irq_s) is
  begin
    case to_integer(mem_addr_s) is
      when 16#42# =>
        mem_r_data_s <= "0" & hpd_s & "000000";
      when 16#96# =>
        mem_r_data_s <= hpd_irq_s & "0000000";
      when others =>
        mem_r_data_s <= regs_s(to_integer(mem_addr_s));
    end case;
  end process;

  irq_n_s <= not hpd_irq_s;

  chip_write: process(clock_s) is
    variable last_hpd: std_ulogic := '0';
  begin
    if rising_edge(clock_s) then
      if mem_w_valid_s = '1' then
        if to_integer(mem_addr_s) = 16#96# then
          if mem_w_data_s(7) = '1' then
            hpd_irq_s <= '0';
          end if;
        elsif hpd_s = '1' then
          regs_s(to_integer(mem_addr_s)) <= mem_w_data_s;
        end if;
      end if;

      if hpd_s /= last_hpd then
        hpd_irq_s <= '1';
        if hpd_s = '0' then
          regs_s <= (others => x"00");
        end if;
      end if;
      last_hpd := hpd_s;
    end if;
  end process;

  -- Shortest SCL period seen, checked against the one the divisor
  -- asks for: the divisor reached the transactor, and the rate is not
  -- the transactor default.
  scl_monitor: process is
    variable last_edge: time := 0 ns;
  begin
    scl_shortest_s <= 1 sec;
    wait until reset_n_s = '1';
    wait until rising_edge(i2c_s.scl);
    last_edge := now;
    loop
      wait until rising_edge(i2c_s.scl);
      if now - last_edge < scl_shortest_s then
        scl_shortest_s <= now - last_edge;
      end if;
      last_edge := now;
    end loop;
  end process;

  control_check: process is
    procedure expect_reg(addr: natural; value: byte) is
    begin
      assert regs_s(addr) = value
        report "Register " & to_hex_string(to_byte(addr)) & " is "
        & to_hex_string(regs_s(addr)) & ", expected " & to_hex_string(value)
        severity failure;
    end procedure;

    procedure expect_configured(msg: string) is
      constant csc_c : byte_string(0 to 23) := from_hex(
        "e73404ad00001c1b1ddc04ad1f240135000004ad087c1b77");
    begin
      wait until ready_s = '1' for 2 sec;
      assert ready_s = '1'
        report msg & ": driver never got ready"
        severity failure;
      assert hpd_out_s = '1'
        report msg & ": hot plug not reported"
        severity failure;
      expect_reg(16#41#, x"10");
      expect_reg(16#98#, x"03");
      expect_reg(16#9a#, x"e0");
      expect_reg(16#9c#, x"30");
      expect_reg(16#9d#, x"61");
      expect_reg(16#a2#, x"a4");
      expect_reg(16#a3#, x"a4");
      expect_reg(16#e0#, x"d0");
      expect_reg(16#15#, x"01");
      expect_reg(16#16#, x"38");
      expect_reg(16#17#, x"02");
      for i in csc_c'range loop
        expect_reg(16#18# + i, csc_c(i));
      end loop;
      expect_reg(16#48#, x"08");
      expect_reg(16#55#, x"10");
      expect_reg(16#56#, x"28");
      expect_reg(16#57#, x"08");
      expect_reg(16#ba#, x"60");
      expect_reg(16#01#, x"00");
      expect_reg(16#02#, x"18");
      expect_reg(16#03#, x"00");
      expect_reg(16#0a#, x"10");
      expect_reg(16#0b#, x"8e");
      expect_reg(16#af#, x"06");
    end procedure;
  begin
    wait until reset_n_s = '1';

    -- No sink: driver keeps polling, never configures
    wait for 20 ms;
    assert ready_s = '0' and hpd_out_s = '0'
      report "Driver configured without a sink"
      severity failure;

    hpd_s <= '1';
    expect_configured("first plug");

    -- Sink goes away: configuration is lost
    hpd_s <= '0';
    wait until ready_s = '0' for 100 ms;
    assert ready_s = '0' and hpd_out_s = '0'
      report "Unplug not noticed"
      severity failure;

    hpd_s <= '1';
    expect_configured("second plug");

    assert scl_shortest_s >= scl_period_c and scl_shortest_s <= scl_period_c * 5 / 4
      report "Fastest SCL period is " & time'image(scl_shortest_s)
      & ", expected " & time'image(scl_period_c)
      severity failure;

    if not video_done_s then
      wait until video_done_s;
    end if;
    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

  -- Video domain

  source: process is
    variable p: pixel_t;
  begin
    pixel_s.m <= transfer(config_c, pixel_zero_c, valid => false);
    wait until pixel_reset_n_s = '1';

    loop
      for y in 0 to v_act_c - 1 loop
        for x in 0 to h_act_c - 1 loop
          p := pixel_zero_c;
          p(0) := to_unsigned(luma(x, y), max_component_bits_c);
          p(1) := to_unsigned(chroma(x, y), max_component_bits_c);
          wait until falling_edge(pixel_clock_s);
          pixel_s.m <= transfer(config_c, p,
                                sof => x = 0 and y = 0,
                                last => x = h_act_c - 1,
                                eof => x = h_act_c - 1 and y = v_act_c - 1);
          wait until rising_edge(pixel_clock_s) and is_ready(config_c, pixel_s.s);
        end loop;
      end loop;
    end loop;
  end process;

  video_check: process is
    variable y: natural;
  begin
    wait until pixel_reset_n_s = '1';
    wait until rising_edge(pixel_clock_s) and synced_s = '1';

    -- Align on a frame: vsync is active high
    wait until rising_edge(pixel_clock_s) and hd_vsync_s = '1';
    wait until rising_edge(pixel_clock_s) and hd_vsync_s = '0';

    for frame in 0 to 1 loop
      y := 0;
      while y < v_act_c loop
        wait until rising_edge(pixel_clock_s);
        assert hd_vsync_s = '0'
          report "vsync in active area"
          severity failure;
        if hd_de_s = '1' then
          for x in 0 to h_act_c - 1 loop
            assert hd_de_s = '1'
              report "Short line"
              severity failure;
            assert hd_hsync_s = '1'
              report "hsync in active area"
              severity failure;
            assert unsigned(hd_data_s(7 downto 0)) = luma(x, y)
              report "Bad luma at " & integer'image(x) & "," & integer'image(y)
              & ": " & to_hex_string(hd_data_s)
              severity failure;
            assert unsigned(hd_data_s(15 downto 8)) = chroma(x, y)
              report "Bad chroma at " & integer'image(x) & "," & integer'image(y)
              & ": " & to_hex_string(hd_data_s)
              severity failure;
            wait until rising_edge(pixel_clock_s);
          end loop;
          assert hd_de_s = '0'
            report "Long line"
            severity failure;
          y := y + 1;
        end if;
      end loop;

      -- Blanking until next frame
      wait until rising_edge(pixel_clock_s) and hd_vsync_s = '1';
      assert hd_de_s = '0'
        report "Data enable during vsync"
        severity failure;
      wait until rising_edge(pixel_clock_s) and hd_vsync_s = '0';
    end loop;

    video_done_s <= true;
    wait;
  end process;

  watchdog: process is
  begin
    wait for 3 sec;
    assert false report "Timeout" severity failure;
  end process;

end architecture;
