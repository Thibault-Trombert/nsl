library ieee;
use ieee.std_logic_1164.all;

library nsl_math;

-- Single-clock FIFO over a memory array written synchronously at a
-- write index and read asynchronously at a read index.
--
-- The array is the only storage for words. An asynchronous read port
-- is what LUT RAM offers (Gowin SSRAM, Xilinx distributed RAM, Lattice
-- DPR16X4) and what block RAM does not, so synthesizers map it to LUT
-- RAM without being told. A target without LUT RAM builds it from
-- registers and a read multiplexer.
--
-- Both indices wrap at word_count_c. Registered empty and full flags
-- tell apart the two cases where indices are equal; each is only set
-- on the transition that makes the one index catch up with the other,
-- which takes one comparison between an incremented index and the
-- other index. An index wraps by comparison to the last one, so
-- word_count_c needs not be a power of two; a power of two only saves
-- that comparison.
--
-- The one-hot fill register only feeds fill_o, and synthesis drops it
-- when fill_o is left open.
entity fifo_lutram is
  generic(
    data_width_c: natural;
    word_count_c: positive
    );
  port(
    reset_n_i: in std_ulogic;
    clock_i: in std_ulogic;

    in_data_i: in std_ulogic_vector(data_width_c-1 downto 0);
    in_valid_i: in std_ulogic;
    in_ready_o: out std_ulogic;

    out_data_o: out std_ulogic_vector(data_width_c-1 downto 0);
    out_valid_o: out std_ulogic;
    out_ready_i: in std_ulogic;

    fill_o: out std_ulogic_vector(0 to word_count_c)
    );
end entity;

architecture beh of fifo_lutram is

  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);
  type word_vector_t is array(natural range <>) of word_t;
  subtype index_t is natural range 0 to word_count_c-1;

  constant is_pow2_c: boolean := nsl_math.arith.is_pow2(word_count_c);

  function index_next(i: index_t) return index_t
  is
  begin
    if is_pow2_c then
      return (i + 1) mod word_count_c;
    elsif i = word_count_c - 1 then
      return 0;
    else
      return i + 1;
    end if;
  end function;

  type regs_t is
  record
    write_index: index_t;
    read_index: index_t;
    empty: boolean;
    full: boolean;
    pos: std_ulogic_vector(0 to word_count_c);
  end record;

  signal r, rin: regs_t;

  signal storage: word_vector_t(0 to word_count_c-1);

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.write_index <= 0;
      r.read_index <= 0;
      r.empty <= true;
      r.full <= false;
      r.pos <= (0 => '1', others => '0');
    end if;
  end process;

  transition: process(r, in_valid_i, out_ready_i) is
    variable push, pop: boolean;
  begin
    push := in_valid_i = '1' and not r.full;
    pop := out_ready_i = '1' and not r.empty;

    rin <= r;

    if push then
      rin.write_index <= index_next(r.write_index);
    end if;

    if pop then
      rin.read_index <= index_next(r.read_index);
    end if;

    if push and not pop then
      rin.empty <= false;
      rin.full <= index_next(r.write_index) = r.read_index;
      rin.pos(0) <= '0';
      for i in 1 to word_count_c
      loop
        rin.pos(i) <= r.pos(i-1);
      end loop;
    elsif pop and not push then
      rin.full <= false;
      rin.empty <= index_next(r.read_index) = r.write_index;
      for i in 0 to word_count_c-1
      loop
        rin.pos(i) <= r.pos(i+1);
      end loop;
      rin.pos(word_count_c) <= '0';
    end if;
  end process;

  write_port: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      if in_valid_i = '1' and not r.full then
        storage(r.write_index) <= in_data_i;
      end if;
    end if;
  end process;

  read_port: process(storage, r) is
  begin
    out_data_o <= storage(r.read_index);
  end process;

  moore: process(r) is
  begin
    if r.full then
      in_ready_o <= '0';
    else
      in_ready_o <= '1';
    end if;

    if r.empty then
      out_valid_o <= '0';
    else
      out_valid_o <= '1';
    end if;

    fill_o <= r.pos;
  end process;

end architecture;
