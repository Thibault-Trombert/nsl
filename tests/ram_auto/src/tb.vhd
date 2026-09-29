library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_hwconfig, nsl_memory, nsl_simulation;
use nsl_hwconfig.memory_config.all;
use nsl_memory.ram.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- One ram_auto instance against a reference model.
--
-- The whole memory is written first, then random writes (random lane
-- enables) and reads (random read enables) go on every cycle.  Read
-- data is checked every cycle against the model of the documented
-- latency: a single register, or a two-stage pipeline advancing on
-- read enable.  Lanes read on the edge they are written are
-- undefined and not checked.  Inputs are driven on falling edges, and
-- outputs checked there too, where the last rising edge settled them.
entity ram_auto_harness is
  generic(
    name_c: string;
    addr_size_c: natural;
    word_size_c: positive;
    data_word_count_c: positive;
    registered_output_c: boolean;
    lutram_primitives_max_c: natural;
    expected_c: ram_implementation_t;
    seed_c: positive;
    cycles_c: natural := 3000
    );
  port(
    clock_i: in std_ulogic;
    done_o: out std_ulogic
    );
end entity;

architecture beh of ram_auto_harness is

  constant width_c: natural := word_size_c * data_word_count_c;
  constant words_c: natural := 2 ** addr_size_c;

  subtype word_t is std_ulogic_vector(width_c-1 downto 0);
  subtype lanes_t is std_ulogic_vector(data_word_count_c-1 downto 0);
  type word_vector_t is array(natural range <>) of word_t;

  signal write_address_s, read_address_s: unsigned(addr_size_c-1 downto 0);
  signal write_en_s: lanes_t;
  signal write_data_s, read_data_s: word_t;
  signal read_en_s: std_ulogic;

begin

  dut: nsl_memory.ram.ram_auto
    generic map(
      addr_size_c => addr_size_c,
      word_size_c => word_size_c,
      data_word_count_c => data_word_count_c,
      registered_output_c => registered_output_c,
      lutram_primitives_max_c => lutram_primitives_max_c
      )
    port map(
      clock_i => clock_i,
      write_address_i => write_address_s,
      write_en_i => write_en_s,
      write_data_i => write_data_s,
      read_address_i => read_address_s,
      read_en_i => read_en_s,
      read_data_o => read_data_s
      );

  stim: process is
    constant ctx: log_context := name_c;
    variable s1, s2: positive;
    variable x: real;

    variable model: word_vector_t(0 to words_c-1);

    -- Inputs of the rising edge to come.
    variable w_address, r_address: natural range 0 to words_c-1;
    variable w_en: lanes_t;
    variable w_data: word_t;
    variable r_en: boolean;

    -- Read pipeline model, and which lanes of it are defined.
    variable stage, expected: word_t;
    variable stage_known, expected_known, collided: lanes_t;

    variable checks, writes, holds: natural := 0;

    impure function random(n: positive) return natural is
    begin
      uniform(s1, s2, x);
      return integer(floor(x * real(n))) mod n;
    end function;

    impure function random_word return word_t is
      variable ret: word_t;
    begin
      for i in ret'range
      loop
        if random(2) = 1 then
          ret(i) := '1';
        else
          ret(i) := '0';
        end if;
      end loop;
      return ret;
    end function;

    function lane(w: word_t; i: natural) return std_ulogic_vector is
    begin
      return w((i+1)*word_size_c-1 downto i*word_size_c);
    end function;

    procedure drive is
    begin
      write_address_s <= to_unsigned(w_address, addr_size_c);
      write_en_s <= w_en;
      write_data_s <= w_data;
      read_address_s <= to_unsigned(r_address, addr_size_c);
      if r_en then
        read_en_s <= '1';
      else
        read_en_s <= '0';
      end if;
    end procedure;

    -- What the rising edge between the last drive and now did.
    procedure edge is
      variable value: word_t;
    begin
      if r_en then
        value := model(r_address);
        collided := (others => '0');
        if w_address = r_address then
          collided := w_en;
        end if;

        if registered_output_c then
          expected := stage;
          expected_known := stage_known;
          stage := value;
          stage_known := not collided;
        else
          expected := value;
          expected_known := not collided;
        end if;
      else
        holds := holds + 1;
      end if;

      for i in 0 to data_word_count_c-1
      loop
        if w_en(i) = '1' then
          model(w_address)((i+1)*word_size_c-1 downto i*word_size_c)
            := lane(w_data, i);
        end if;
      end loop;
    end procedure;

    procedure check is
    begin
      for i in 0 to data_word_count_c-1
      loop
        if expected_known(i) = '1' then
          assert_equal(ctx, "lane " & integer'image(i),
                       lane(read_data_s, i), lane(expected, i), failure);
          checks := checks + 1;
        end if;
      end loop;
    end procedure;

  begin
    s1 := seed_c;
    s2 := seed_c * 7 + 3;
    done_o <= '0';

    assert_equal(ctx, "implementation",
                 ram_implementation_t'image(
                   ram_auto_implementation(addr_size_c, width_c,
                                           nsl_hwconfig.memory_config.lutram,
                                           lutram_primitives_max_c)),
                 ram_implementation_t'image(expected_c), failure);

    stage_known := (others => '0');
    expected_known := (others => '0');
    r_en := false;
    r_address := 0;
    w_en := (others => '0');
    w_address := 0;
    w_data := (others => '0');
    drive;

    -- Fill every word, whole.
    for a in 0 to words_c-1
    loop
      wait until falling_edge(clock_i);
      edge;
      w_address := a;
      w_en := (others => '1');
      w_data := random_word;
      drive;
    end loop;

    for c in 0 to cycles_c-1
    loop
      wait until falling_edge(clock_i);
      edge;
      check;

      w_address := random(words_c);
      w_data := random_word;
      for i in 0 to data_word_count_c-1
      loop
        if random(3) = 0 then
          w_en(i) := '1';
        else
          w_en(i) := '0';
        end if;
      end loop;
      if w_en /= (w_en'range => '0') then
        writes := writes + 1;
      end if;

      -- Now and then, read the word being written.
      if random(8) = 0 then
        r_address := w_address;
      else
        r_address := random(words_c);
      end if;
      r_en := random(4) /= 0;
      drive;
    end loop;

    wait until falling_edge(clock_i);
    edge;
    check;

    assert checks > cycles_c / 2 and writes > cycles_c / 4 and holds > cycles_c / 8
      report name_c & ": too few checks, writes or holds"
      severity failure;

    log_info(ctx, "done, " & integer'image(checks) & " lane checks");
    done_o <= '1';
    wait;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;

library nsl_hwconfig, nsl_memory, nsl_simulation;
use nsl_hwconfig.memory_config.all;
use nsl_memory.ram.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- ram_auto regression.
--
-- The selection rule is checked on its own against LUT RAM facts of
-- several kinds of targets.  Then instances of either implementation,
-- with and without a registered output and byte lanes, each checked
-- against a model by ram_auto_harness.  Simulation answers as a target
-- with 16x4 LUT RAM, so small memories select LUT RAM, large ones
-- block RAM; the budget generic forces either on the other ones.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 7);

  procedure check_rules
  is
    constant ctx: log_context := "rules";

    constant gowin_c: lutram_t := (present => true, async_read => true,
                                   depth => 16, width => 4,
                                   fifo_depth_max => 64);
    constant xilinx_c: lutram_t := (present => true, async_read => true,
                                    depth => 32, width => 6,
                                    fifo_depth_max => 128);
    constant agilex_c: lutram_t := (present => true, async_read => true,
                                    depth => 32, width => 20,
                                    fifo_depth_max => 64);
    constant none_c: lutram_t := (present => false, async_read => false,
                                  depth => 0, width => 0,
                                  fifo_depth_max => 0);
    constant sync_read_c: lutram_t := (present => true, async_read => false,
                                       depth => 16, width => 4,
                                       fifo_depth_max => 64);

    procedure expect(what: string;
                     addr_size, width: natural;
                     lutram: lutram_t;
                     expected: ram_implementation_t;
                     budget: natural := ram_auto_lutram_primitives_max_c)
    is
      constant got: ram_implementation_t
        := ram_auto_implementation(addr_size, width, lutram, budget);
    begin
      assert_equal(ctx, what,
                   ram_implementation_t'image(got),
                   ram_implementation_t'image(expected),
                   failure);
    end procedure;
  begin
    -- Gowin, 16x4 primitives, 16 of them by default.
    expect("gowin 8x32", 3, 32, gowin_c, RAM_IMPLEMENTATION_LUTRAM);
    expect("gowin 32x32", 5, 32, gowin_c, RAM_IMPLEMENTATION_LUTRAM);
    expect("gowin 32x33", 5, 33, gowin_c, RAM_IMPLEMENTATION_BLOCK);
    expect("gowin 64x32", 6, 32, gowin_c, RAM_IMPLEMENTATION_BLOCK);
    expect("gowin 256x4", 8, 4, gowin_c, RAM_IMPLEMENTATION_LUTRAM);
    expect("gowin 256x1", 8, 1, gowin_c, RAM_IMPLEMENTATION_LUTRAM);
    expect("gowin 512x1", 9, 1, gowin_c, RAM_IMPLEMENTATION_BLOCK);
    expect("gowin 2x1", 1, 1, gowin_c, RAM_IMPLEMENTATION_LUTRAM);

    -- The budget.
    expect("gowin 2x1, no budget", 1, 1, gowin_c, RAM_IMPLEMENTATION_BLOCK, 0);
    expect("gowin 64x32, 32", 6, 32, gowin_c, RAM_IMPLEMENTATION_LUTRAM, 32);
    expect("gowin 64x32, 31", 6, 32, gowin_c, RAM_IMPLEMENTATION_BLOCK, 31);

    -- Other geometries.
    expect("xilinx 32x32", 5, 32, xilinx_c, RAM_IMPLEMENTATION_LUTRAM);
    expect("xilinx 64x48", 6, 48, xilinx_c, RAM_IMPLEMENTATION_LUTRAM);
    expect("xilinx 64x54", 6, 54, xilinx_c, RAM_IMPLEMENTATION_BLOCK);
    expect("agilex 256x40", 8, 40, agilex_c, RAM_IMPLEMENTATION_LUTRAM);
    expect("agilex 512x40", 9, 40, agilex_c, RAM_IMPLEMENTATION_BLOCK);

    -- Without LUT RAM, or without asynchronous read: block RAM.
    expect("none 2x1", 1, 1, none_c, RAM_IMPLEMENTATION_BLOCK);
    expect("none 2x1, any budget", 1, 1, none_c, RAM_IMPLEMENTATION_BLOCK, natural'high);
    expect("sync read 16x4", 4, 4, sync_read_c, RAM_IMPLEMENTATION_BLOCK);

    log_info(ctx, "done");
  end procedure;

begin

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 20 ns,
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

  rules: process is
  begin
    done_s(0) <= '0';
    check_rules;
    done_s(0) <= '1';
    wait;
  end process;

  lut_small: entity work.ram_auto_harness
    generic map(
      name_c => "lut 16x8",
      addr_size_c => 4, word_size_c => 8, data_word_count_c => 1,
      registered_output_c => false,
      lutram_primitives_max_c => ram_auto_lutram_primitives_max_c,
      expected_c => RAM_IMPLEMENTATION_LUTRAM,
      seed_c => 1)
    port map(clock_i => clock_s, done_o => done_s(1));

  lut_lanes: entity work.ram_auto_harness
    generic map(
      name_c => "lut 32x4x8 registered",
      addr_size_c => 5, word_size_c => 8, data_word_count_c => 4,
      registered_output_c => true,
      lutram_primitives_max_c => ram_auto_lutram_primitives_max_c,
      expected_c => RAM_IMPLEMENTATION_LUTRAM,
      seed_c => 2)
    port map(clock_i => clock_s, done_o => done_s(2));

  block_lanes: entity work.ram_auto_harness
    generic map(
      name_c => "block 256x2x8 registered",
      addr_size_c => 8, word_size_c => 8, data_word_count_c => 2,
      registered_output_c => true,
      lutram_primitives_max_c => ram_auto_lutram_primitives_max_c,
      expected_c => RAM_IMPLEMENTATION_BLOCK,
      seed_c => 3)
    port map(clock_i => clock_s, done_o => done_s(3));

  block_wide: entity work.ram_auto_harness
    generic map(
      name_c => "block 64x32",
      addr_size_c => 6, word_size_c => 32, data_word_count_c => 1,
      registered_output_c => false,
      lutram_primitives_max_c => ram_auto_lutram_primitives_max_c,
      expected_c => RAM_IMPLEMENTATION_BLOCK,
      seed_c => 4)
    port map(clock_i => clock_s, done_o => done_s(4));

  forced_block: entity work.ram_auto_harness
    generic map(
      name_c => "forced block 16x3x5 registered",
      addr_size_c => 4, word_size_c => 5, data_word_count_c => 3,
      registered_output_c => true,
      lutram_primitives_max_c => 0,
      expected_c => RAM_IMPLEMENTATION_BLOCK,
      seed_c => 5)
    port map(clock_i => clock_s, done_o => done_s(5));

  forced_lut: entity work.ram_auto_harness
    generic map(
      name_c => "forced lut 256x16",
      addr_size_c => 8, word_size_c => 16, data_word_count_c => 1,
      registered_output_c => false,
      lutram_primitives_max_c => natural'high,
      expected_c => RAM_IMPLEMENTATION_LUTRAM,
      seed_c => 6)
    port map(clock_i => clock_s, done_o => done_s(6));

  tiny: entity work.ram_auto_harness
    generic map(
      name_c => "lut 2x1 registered",
      addr_size_c => 1, word_size_c => 1, data_word_count_c => 1,
      registered_output_c => true,
      lutram_primitives_max_c => ram_auto_lutram_primitives_max_c,
      expected_c => RAM_IMPLEMENTATION_LUTRAM,
      seed_c => 7)
    port map(clock_i => clock_s, done_o => done_s(7));

  watchdog: process is
  begin
    wait for 1 ms;
    assert false
      report "Timeout"
      severity failure;
    wait;
  end process;

end architecture;
