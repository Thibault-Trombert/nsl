library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_data.prbs.all;
use nsl_amba.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is

  signal in_clock_s, in_reset_n_s : std_ulogic;
  signal out_clock_s, out_reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  signal input_s, output_s: bus_t;

  constant cfg_c: config_t := config(12, last => true);

begin

  tx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable frame_byte_count: integer;
  begin
    done_s(0) <= '0';

    input_s.m <= transfer_defaults(cfg_c);

    wait for 100 ns;

    for stream_beat_count in 1 to 16
    loop
      frame_byte_count := stream_beat_count * cfg_c.data_width;

      packet_send(cfg_c, in_clock_s, input_s.s, input_s.m,
                  packet => prbs_byte_string(state_v, prbs31, frame_byte_count));

      state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);
    end loop;

    wait for 500 ns;

    done_s(0) <= '1';
    wait;
  end process;

  rx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable rx_data : byte_stream;
    variable frame_byte_count: integer;
    variable id, user, dest : std_ulogic_vector(1 to 0);
  begin
    done_s(1) <= '0';

    output_s.s <= accept(cfg_c, false);

    wait for 100 ns;

    for stream_beat_count in 1 to 16
    loop
      frame_byte_count := stream_beat_count * cfg_c.data_width;

      packet_receive(cfg_c, out_clock_s, output_s.m, output_s.s,
                     packet => rx_data,
                     id => id,
                     user => user,
                     dest => dest,
	     	     ready_toggle => true);

      assert_equal("data", rx_data.all(0 to frame_byte_count-1), prbs_byte_string(state_v, prbs31, frame_byte_count), failure);
      state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);
    end loop;

    wait for 500 ns;

    done_s(1) <= '1';
    wait;
  end process;

  dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "IN"
      )
    port map(
      clock_i => in_clock_s,
      reset_n_i => in_reset_n_s,

      bus_i => input_s
      );

  dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "OUT"
      )
    port map(
      clock_i => out_clock_s,
      reset_n_i => out_reset_n_s,

      bus_i => output_s
      );
  
  dut: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      depth_c => 16,
      config_c => cfg_c,
      clock_count_c => 2
      )
    port map(
      clock_i(0) => in_clock_s,
      clock_i(1) => out_clock_s,
      reset_n_i => in_reset_n_s,

      in_i => input_s.m,
      in_o => input_s.s,

      out_o => output_s.m,
      out_i => output_s.s
      );
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 7 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => in_clock_s,
      clock_o(1) => out_clock_s,
      reset_n_o(0) => in_reset_n_s,
      done_i => done_s
      );
  
end;
