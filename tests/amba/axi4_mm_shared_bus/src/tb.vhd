library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_mm.all;
use nsl_amba.address.all;
use nsl_amba.mm_routing.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  -- Single configuration for shared bus (no ID widening)
  constant config_c : config_t := config(
    address_width => 32,
    data_bus_width => 32,
    id_width => 4,
    max_length => 16,
    burst => true
    );

  constant master_count_c : positive := 2;
  constant slave_count_c : positive := 2;

  -- Routing table: slave 0 at 0x00000000, slave 1 at 0x10000000
  constant routing_table_c : nsl_amba.address.address_vector := routing_table(
    32,
    "x0-------/4",  -- 0x00000000 - 0x0FFFFFFF -> slave 0
    "x1-------/4"   -- 0x10000000 - 0x1FFFFFFF -> slave 1
    );

  -- Master side buses (from masters to interconnect)
  signal master_bus : bus_vector(0 to master_count_c-1);

  -- Slave side buses (from interconnect to slaves)
  signal slave_bus : bus_vector(0 to slave_count_c-1);

begin

  -- Master 0 test process (higher priority)
  -- Tests: writes and reads to slave 0 and slave 1, plus unmapped address
  master0: process is
    variable rsp: resp_enum_t;
    variable dummy_data : byte_string(0 to 3);
  begin
    done_s(0) <= '0';

    master_bus(0).m.ar <= address_defaults(config_c);
    master_bus(0).m.r <= handshake_defaults(config_c);
    master_bus(0).m.aw <= address_defaults(config_c);
    master_bus(0).m.w <= write_data_defaults(config_c);
    master_bus(0).m.b <= accept(config_c, true);

    wait for 50 ns;
    wait until falling_edge(clock_s);

    -- Write to slave 0 at base address
    log_info("Master 0: Writing to slave 0 at 0x00000000");
    burst_write(config_c, clock_s, master_bus(0).s, master_bus(0).m,
                x"00000000", from_hex("deadbeef"),
                rsp => rsp);
    assert rsp = RESP_OKAY
      report "Master 0 write to slave 0: expected OKAY, got " & to_string(rsp)
      severity failure;

    -- Write a longer burst to slave 0 at different address
    log_info("Master 0: Writing 16-byte burst to slave 0 at 0x00000100");
    burst_write(config_c, clock_s, master_bus(0).s, master_bus(0).m,
                x"00000100", from_hex("00112233445566778899aabbccddeeff"),
                rsp => rsp);
    assert rsp = RESP_OKAY
      report "Master 0 burst write to slave 0: expected OKAY, got " & to_string(rsp)
      severity failure;

    -- Write to slave 1
    log_info("Master 0: Writing to slave 1 at 0x10000000");
    burst_write(config_c, clock_s, master_bus(0).s, master_bus(0).m,
                x"10000000", from_hex("cafebabe"),
                rsp => rsp);
    assert rsp = RESP_OKAY
      report "Master 0 write to slave 1: expected OKAY, got " & to_string(rsp)
      severity failure;

    -- Read back from slave 0
    log_info("Master 0: Reading from slave 0 at 0x00000000");
    burst_check(config_c, clock_s, master_bus(0).s, master_bus(0).m,
                x"00000000", from_hex("deadbeef"));

    -- Read back burst from slave 0
    log_info("Master 0: Reading 16-byte burst from slave 0 at 0x00000100");
    burst_check(config_c, clock_s, master_bus(0).s, master_bus(0).m,
                x"00000100", from_hex("00112233445566778899aabbccddeeff"));

    -- Read back from slave 1
    log_info("Master 0: Reading from slave 1 at 0x10000000");
    burst_check(config_c, clock_s, master_bus(0).s, master_bus(0).m,
                x"10000000", from_hex("cafebabe"));

    -- Try unmapped address (should get DECERR with internal error slave)
    log_info("Master 0: Writing to unmapped address at 0x20000000");
    burst_write(config_c, clock_s, master_bus(0).s, master_bus(0).m,
                x"20000000", from_hex("12345678"),
                rsp => rsp);
    assert rsp = RESP_DECERR
      report "Master 0 write to unmapped address: expected DECERR, got " & to_string(rsp)
      severity failure;

    -- Read from unmapped address (should get DECERR)
    log_info("Master 0: Reading from unmapped address at 0x30000000");
    burst_read(config_c, clock_s, master_bus(0).s, master_bus(0).m,
               x"30000000", dummy_data, rsp);
    assert rsp = RESP_DECERR
      report "Master 0 read from unmapped address: expected DECERR, got " & to_string(rsp)
      severity failure;

    log_info("Master 0: Test complete");
    done_s(0) <= '1';
    wait;
  end process;

  -- Master 1 test process (lower priority)
  -- Tests sequential access since shared bus is single-issue
  master1: process is
    variable rsp: resp_enum_t;
    variable dummy_data : byte_string(0 to 3);
  begin
    done_s(1) <= '0';

    master_bus(1).m.ar <= address_defaults(config_c);
    master_bus(1).m.r <= handshake_defaults(config_c);
    master_bus(1).m.aw <= address_defaults(config_c);
    master_bus(1).m.w <= write_data_defaults(config_c);
    master_bus(1).m.b <= accept(config_c, true);

    -- Wait longer to let master 0 get some transactions through first
    -- This tests priority arbitration behavior
    wait for 200 ns;
    wait until falling_edge(clock_s);

    -- Write to slave 1
    log_info("Master 1: Writing to slave 1 at 0x10000200");
    burst_write(config_c, clock_s, master_bus(1).s, master_bus(1).m,
                x"10000200", from_hex("11223344"),
                rsp => rsp);
    assert rsp = RESP_OKAY
      report "Master 1 write to slave 1: expected OKAY, got " & to_string(rsp)
      severity failure;

    -- Write to slave 0
    log_info("Master 1: Writing to slave 0 at 0x00000200");
    burst_write(config_c, clock_s, master_bus(1).s, master_bus(1).m,
                x"00000200", from_hex("55667788"),
                rsp => rsp);
    assert rsp = RESP_OKAY
      report "Master 1 write to slave 0: expected OKAY, got " & to_string(rsp)
      severity failure;

    -- Write longer burst to slave 1
    log_info("Master 1: Writing 12-byte burst to slave 1 at 0x10000300");
    burst_write(config_c, clock_s, master_bus(1).s, master_bus(1).m,
                x"10000300", from_hex("aabbccddeeff00112233"),
                rsp => rsp);
    assert rsp = RESP_OKAY
      report "Master 1 burst write to slave 1: expected OKAY, got " & to_string(rsp)
      severity failure;

    -- Read back from slave 1
    log_info("Master 1: Reading from slave 1 at 0x10000200");
    burst_check(config_c, clock_s, master_bus(1).s, master_bus(1).m,
                x"10000200", from_hex("11223344"));

    -- Read back from slave 0
    log_info("Master 1: Reading from slave 0 at 0x00000200");
    burst_check(config_c, clock_s, master_bus(1).s, master_bus(1).m,
                x"00000200", from_hex("55667788"));

    -- Read back burst from slave 1
    log_info("Master 1: Reading 12-byte burst from slave 1 at 0x10000300");
    burst_check(config_c, clock_s, master_bus(1).s, master_bus(1).m,
                x"10000300", from_hex("aabbccddeeff00112233"));

    -- Try unmapped address (should get DECERR)
    log_info("Master 1: Reading from unmapped address at 0x40000000");
    burst_read(config_c, clock_s, master_bus(1).s, master_bus(1).m,
               x"40000000", dummy_data, rsp);
    assert rsp = RESP_DECERR
      report "Master 1 read from unmapped address: expected DECERR, got " & to_string(rsp)
      severity failure;

    log_info("Master 1: Test complete");
    done_s(1) <= '1';
    wait;
  end process;

  -- DUT: AXI4-MM shared bus interconnect
  dut: axi4_mm_shared_bus
    generic map(
      config_c => config_c,
      master_count_c => master_count_c,
      routing_table_c => routing_table_c,
      default_slave_c => -1  -- Use internal error slave
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      slave_i(0) => master_bus(0).m,
      slave_i(1) => master_bus(1).m,
      slave_o(0) => master_bus(0).s,
      slave_o(1) => master_bus(1).s,
      master_o(0) => slave_bus(0).m,
      master_o(1) => slave_bus(1).m,
      master_i(0) => slave_bus(0).s,
      master_i(1) => slave_bus(1).s
      );

  -- Slave 0: RAM
  ram0: nsl_amba.ram.axi4_mm_ram
    generic map(
      config_c => config_c,
      byte_size_l2_c => 10
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      axi_i => slave_bus(0).m,
      axi_o => slave_bus(0).s
      );

  -- Slave 1: RAM
  ram1: nsl_amba.ram.axi4_mm_ram
    generic map(
      config_c => config_c,
      byte_size_l2_c => 10
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      axi_i => slave_bus(1).m,
      axi_o => slave_bus(1).s
      );

  -- Dumpers for debugging
  dumper_m0: nsl_amba.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => config_c,
      prefix_c => "M0"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      master_i => master_bus(0).m,
      slave_i => master_bus(0).s
      );

  dumper_m1: nsl_amba.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => config_c,
      prefix_c => "M1"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      master_i => master_bus(1).m,
      slave_i => master_bus(1).s
      );

  dumper_s0: nsl_amba.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => config_c,
      prefix_c => "S0"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      master_i => slave_bus(0).m,
      slave_i => slave_bus(0).s
      );

  dumper_s1: nsl_amba.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => config_c,
      prefix_c => "S1"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      master_i => slave_bus(1).m,
      slave_i => slave_bus(1).s
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 50 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
