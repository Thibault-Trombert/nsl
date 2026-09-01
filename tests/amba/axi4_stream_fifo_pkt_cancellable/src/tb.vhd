library ieee, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb is
end tb;

library nsl_memory, nsl_simulation, nsl_amba, nsl_data, nsl_logic;
use nsl_data.bytestream.all;
use nsl_amba.axi4_stream.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_logic.bool.all;

architecture arch of tb is

  constant cfg_c          : config_t := config(4, keep => true, last => true);
  constant nbr_of_region  : integer  := 4;
  constant word_count_l2  : integer  := 8;

  signal in_clock_s, in_reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  signal input_s, output_s : bus_t;

  signal do_in_commit_s, do_in_rollback_s, do_out_commit_s, do_out_rollback_s : std_ulogic;

  type side_t is record
    clock    : std_ulogic;
    commit   : std_ulogic;
    rollback : std_ulogic;
  end record;

  signal t, r : side_t;

  procedure do_commit(signal clock  : in  std_ulogic;
                      signal commit : out std_ulogic) is
  begin
    commit <= '1';
    wait until rising_edge(clock);
    wait until falling_edge(clock);
    commit <= '0';
  end procedure;

  procedure do_rollback(signal clock    : in  std_ulogic;
                        signal rollback : out std_ulogic) is
  begin
    rollback <= '1';
    wait until rising_edge(clock);
    wait until falling_edge(clock);
    rollback <= '0';
  end procedure;
  
  shared variable in_q, out_q : frame_queue_root_t;
begin

  scenario : process 
    variable frm_col_v : frame_t;
  begin 
    frame_queue_init(in_q);
    frame_queue_init(out_q);
    do_in_commit_s <= '0';
    do_in_rollback_s <= '0';
    do_out_commit_s <= '0';
    do_out_rollback_s <= '0';
    wait until in_reset_n_s = '1';

    do_commit(in_clock_s, do_in_commit_s);
    do_commit(in_clock_s, do_in_commit_s);
    do_commit(in_clock_s, do_in_commit_s);
    do_commit(in_clock_s, do_in_commit_s);

    frame_queue_put(in_q, from_hex("a3"));
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    do_commit(in_clock_s, do_in_commit_s);
    wait until is_last(cfg_c, output_s.m) and is_valid(cfg_c, output_s.m);      
    do_commit(in_clock_s, do_out_commit_s);
    frame_queue_check(out_q, from_hex("a3"));

    log_info("INFO: fill the second group");
    frame_queue_put(in_q, from_hex("de09af3c71"));
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    do_commit(in_clock_s, do_in_commit_s);
    wait until is_last(cfg_c, output_s.m) and is_valid(cfg_c, output_s.m);
    do_commit(in_clock_s, do_out_commit_s);
    frame_queue_check(out_q, from_hex("de09af3c71"));

    log_info("INFO: fill the third group");
    frame_queue_put(in_q, from_hex("f3a850"));
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    do_commit(in_clock_s, do_in_commit_s);
    wait until is_last(cfg_c, output_s.m) and is_valid(cfg_c, output_s.m);
    do_commit(in_clock_s, do_out_commit_s);
    frame_queue_check(out_q, from_hex("f3a850"));

    log_info("INFO: fill the fourth group");
    frame_queue_put(in_q, from_hex("7bc2e853"));                                                                                    
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    do_commit(in_clock_s, do_in_commit_s);
    wait until is_last(cfg_c, output_s.m) and is_valid(cfg_c, output_s.m);
    do_commit(in_clock_s, do_out_commit_s);
    frame_queue_check(out_q, from_hex("7bc2e853"));   

    log_info("INFO: back to r");
    frame_queue_put(in_q, from_hex("e73f12c1"));
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    do_commit(in_clock_s, do_in_commit_s);
    wait until is_last(cfg_c, output_s.m) and is_valid(cfg_c, output_s.m);
    do_commit(in_clock_s, do_out_commit_s);
    frame_queue_check(out_q, from_hex("e73f12c1"));

    do_commit(in_clock_s, do_in_commit_s);
    do_commit(in_clock_s, do_in_commit_s);
    do_commit(in_clock_s, do_in_commit_s);
    do_commit(in_clock_s, do_in_commit_s);

    do_rollback(in_clock_s, do_out_rollback_s);
    do_rollback(in_clock_s, do_out_rollback_s);
    do_rollback(in_clock_s, do_out_rollback_s);
    do_rollback(in_clock_s, do_out_rollback_s);

    log_info("INFO: Test burst");
    frame_queue_put(in_q, from_hex("01"));
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    do_commit(in_clock_s, do_in_commit_s);
    frame_queue_check(out_q, from_hex("01"));   

    frame_queue_put(in_q, from_hex("02"));
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    do_commit(in_clock_s, do_in_commit_s);
    frame_queue_check(out_q, from_hex("02"));   

    frame_queue_put(in_q, from_hex("03"));
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    do_commit(in_clock_s, do_in_commit_s);
    frame_queue_check(out_q, from_hex("03"));   

    frame_queue_put(in_q, from_hex("04"));
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    do_commit(in_clock_s, do_in_commit_s);
    frame_queue_check(out_q, from_hex("04"));   

    wait for 100 ns;
    -- commit "01"
    do_commit(in_clock_s, do_out_commit_s);

    wait for 100 ns;
    do_rollback(in_clock_s, do_out_rollback_s);
    frame_queue_check(out_q, from_hex("02"));   
    frame_queue_check(out_q, from_hex("03"));   
    frame_queue_check(out_q, from_hex("04"));   

    wait for 100 ns;
    -- commit "02"
    do_commit(in_clock_s, do_out_commit_s);
    wait for 100 ns;
    do_rollback(in_clock_s, do_out_rollback_s);
    frame_queue_check(out_q, from_hex("03"));
    frame_queue_check(out_q, from_hex("04"));

    -- commit "03"
    do_commit(in_clock_s, do_out_commit_s);
    -- commit "04"
    do_commit(in_clock_s, do_out_commit_s);

    frame_queue_put(in_q, from_hex("12344569755575552521"));
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    do_commit(in_clock_s, do_in_commit_s);
    frame_queue_check(out_q, from_hex("12344569755575552521"));

    wait for 10 ns;
    do_rollback(in_clock_s, do_out_rollback_s);
    frame_queue_check(out_q, from_hex("12344569755575552521"));

    frame_queue_put(in_q, from_hex("0f0f0f0f"));
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    do_commit(in_clock_s, do_in_commit_s);
    frame_queue_check(out_q, from_hex("0f0f0f0f"));

    wait for 10 ns;
    do_rollback(in_clock_s, do_out_rollback_s);
    frame_queue_check(out_q, from_hex("12344569755575552521"));   
    frame_queue_check(out_q, from_hex("0f0f0f0f"));

    do_in_commit_s <= '1';
    frame_queue_put(in_q, from_hex("afafafafafafafafafafafafafafafaf"));
    frame_queue_put(in_q, from_hex("bfbfbfbf"));
    wait until is_last(cfg_c, input_s.m) and is_valid(cfg_c, input_s.m);
    frame_queue_check(out_q, from_hex("afafafafafafafafafafafafafafafaf"));
    frame_queue_check(out_q, from_hex("bfbfbfbf"));

    assert out_q.head = null
    report "ERROR: data out pending"
    severity failure;

    wait for 1000 ns;
    done_s <= (others => '1');

  end process;

  master_proc : process
  begin 
    wait for 8 ns;
    if in_q.head /= null then
      frame_queue_master(cfg_c, in_q, in_clock_s, input_s.s, input_s.m);
    else 
      input_s.m <= transfer_defaults(cfg_c);
    end if;
  end process;

  slave_proc : process
  begin 
    frame_queue_slave(cfg_c, out_q, in_clock_s, output_s.m, output_s.s);
  end process;

  fifo : nsl_amba.stream_fifo.axi4_stream_fifo_pkt_cancellable
    generic map(
      config_c        => cfg_c,
      word_count_l2_c => word_count_l2,
      out_pkt_available_range_c => 4,
      nbr_of_region   => nbr_of_region
    )
    port map(
      reset_n_i      => in_reset_n_s,
      clock_i        => in_clock_s,

      out_o          => output_s.m,
      out_i          => output_s.s,
      out_commit_i   => do_out_commit_s,
      out_rollback_i => do_out_rollback_s,

      in_i           => input_s.m,
      in_o           => input_s.s,
      in_commit_i    => do_in_commit_s,
      in_rollback_i => do_in_rollback_s
    );

  simdrv : nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count  => done_s'length
    )
    port map(
      clock_period(0)  => 10 ns,
      reset_duration   => (others => 100 ns),
      clock_o(0)       => in_clock_s,
      reset_n_o(0)     => in_reset_n_s,
      done_i           => done_s
    );

end architecture;
