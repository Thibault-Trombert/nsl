library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwconfig;

package ram is

  -- A single-port RAM with registered ouptut.
  component ram_1p
    generic (
      addr_size_c : natural;
      data_size_c : natural
      );
    port (
      clock_i : in std_ulogic;

      address_i : in unsigned(addr_size_c-1 downto 0);
      enable_i : in std_ulogic := '1';

      write_en_i : in std_ulogic;
      write_data_i : in std_ulogic_vector(data_size_c-1 downto 0);

      read_data_o : out std_ulogic_vector(data_size_c-1 downto 0)
      );
  end component;

  -- A single-port RAM with registered ouptut and multi-word write.
  -- Address is base address of data word group
  -- I.e. this memory stores 2**addr_size_c * data_word_count_c * word_size_c bits.
  component ram_1p_multi
    generic (
      addr_size_c : natural;
      word_size_c : natural := 8;
      data_word_count_c : integer := 4
      );
    port (
      clock_i : in std_ulogic;

      address_i : in unsigned(addr_size_c-1 downto 0);
      enable_i : in std_ulogic := '1';

      write_en_i : in std_ulogic_vector(data_word_count_c-1 downto 0);
      write_data_i : in std_ulogic_vector(word_size_c * data_word_count_c-1 downto 0);

      read_data_o : out std_ulogic_vector(word_size_c * data_word_count_c-1 downto 0)
      );
  end component;

  -- A dual-port RAM with optionally two clocks, one port read, one
  -- port write.
  --
  -- Read data appears on interface after rising clock edge.
  -- If read port is disabled, last data is kept on interface, even if read
  -- address changes.
  component ram_2p_r_w
    generic (
      addr_size_c : natural;
      data_size_c : natural;
      clock_count_c : natural range 1 to 2 := 1;
      registered_output_c : boolean := false
      );
    port (
      clock_i : in std_ulogic_vector(0 to clock_count_c-1);

      write_address_i : in unsigned(addr_size_c-1 downto 0);
      write_en_i : in std_ulogic := '0';
      write_data_i : in std_ulogic_vector(data_size_c-1 downto 0) := (others => '-');

      read_address_i : in unsigned(addr_size_c-1 downto 0);
      read_en_i : in std_ulogic := '1';
      read_data_o : out std_ulogic_vector(data_size_c-1 downto 0)
      );
  end component;

  -- Size-homogeneous dual port RAM. Offers parallel read and write
  -- interface of multiple words (each word has an independant
  -- write-strobe signal).
  --
  -- When writing, both enable and write_en signals need to be
  -- asserted.
  --
  -- If registered output is enabled, there is a two rising clock edge
  -- latency between address and data output. If not enabled, there is
  -- only one.
  component ram_2p_homogeneous is
    generic(
      addr_size_c : integer := 10;
      word_size_c : integer := 8;
      data_word_count_c : integer := 4;
      registered_output_c : boolean := false;
      b_can_write_c : boolean := true;
      read_before_write_c : boolean := false
      );
    port(
      a_clock_i : in std_ulogic;
      a_enable_i : in std_ulogic := '1';
      a_write_en_i : in std_ulogic_vector(data_word_count_c - 1 downto 0) := (others => '0');
      a_address_i : in unsigned(addr_size_c - 1 downto 0);
      a_data_i : in std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0) := (others => '-');
      a_data_o : out std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0);
      b_clock_i : in std_ulogic;
      b_enable_i : in std_ulogic := '1';
      b_write_en_i : in std_ulogic_vector(data_word_count_c - 1 downto 0) := (others => '0');
      b_address_i : in unsigned(addr_size_c - 1 downto 0);
      b_data_i : in std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0) := (others => '-');
      b_data_o : out std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0)
      );
  end component;

  -- Dual port ram with port sizes multiple one of another.
  -- All other characteristics match ram_2p_homogeneous
  component ram_2p
    generic (
      a_addr_size_c : natural;
      a_data_byte_count_c : natural;

      b_addr_size_c : natural;
      b_data_byte_count_c : natural;

      registered_output_c : boolean := false
      );
    port (
      a_clock_i : in std_ulogic;
      a_enable_i : in std_ulogic := '1';
      a_address_i : in unsigned(a_addr_size_c-1 downto 0);
      a_write_en_i : in std_ulogic_vector(a_data_byte_count_c-1 downto 0) := (others => '1');
      a_data_i : in std_ulogic_vector(a_data_byte_count_c*8-1 downto 0) := (others => '-');
      a_data_o : out std_ulogic_vector(a_data_byte_count_c*8-1 downto 0);

      b_clock_i : in std_ulogic;
      b_enable_i : in std_ulogic := '1';
      b_address_i : in unsigned(b_addr_size_c-1 downto 0);
      b_write_en_i : in std_ulogic_vector(b_data_byte_count_c-1 downto 0) := (others => '1');
      b_data_i : in std_ulogic_vector(b_data_byte_count_c*8-1 downto 0) := (others => '-');
      b_data_o : out std_ulogic_vector(b_data_byte_count_c*8-1 downto 0)
      );
  end component;

  type ram_implementation_t is (
    RAM_IMPLEMENTATION_LUTRAM,
    RAM_IMPLEMENTATION_BLOCK
    );

  -- LUT RAM primitives (see nsl_hwconfig.memory_config.lutram_t) up to
  -- which ram_auto keeps a memory in LUT RAM by default.
  --
  -- A block RAM is 9 to 20 kbit.  Sixteen Gowin SSRAM or Lattice
  -- DPR16X4 are 1 kbit in the area of about 128 LUT4, where one block
  -- RAM stands for 300 to 500 LUT of the part's fabric; sixteen Xilinx
  -- RAM32M are 3 kbit in 64 LUT6.  A memory this small wastes most of
  -- a block RAM, and costs little fabric.
  constant ram_auto_lutram_primitives_max_c: natural := 16;

  -- Implementation ram_auto selects for a memory of 2**addr_size words
  -- of data_width bits on a target with given LUT RAM resources:
  -- RAM_IMPLEMENTATION_LUTRAM if the target has LUT RAM with
  -- asynchronous read and the memory takes at most
  -- lutram_primitives_max primitives, RAM_IMPLEMENTATION_BLOCK
  -- otherwise.
  function ram_auto_implementation(
    addr_size: natural;
    data_width: natural;
    lutram: nsl_hwconfig.memory_config.lutram_t;
    lutram_primitives_max: natural := ram_auto_lutram_primitives_max_c)
    return ram_implementation_t;

  -- Simple dual-port RAM, one write port, one read port, one clock,
  -- whose implementation is picked at elaboration by
  -- ram_auto_implementation() against the LUT RAM resources of the
  -- target (nsl_hwconfig.memory_config) and lutram_primitives_max_c:
  -- LUT RAM for a small memory, block RAM (ram_2p_homogeneous)
  -- otherwise.  lutram_primitives_max_c of zero always selects block
  -- RAM.
  --
  -- Words are data_word_count_c lanes of word_size_c bits, each lane
  -- with its own write enable.  A lane is written on a rising edge
  -- where its write_en_i bit is set.
  --
  -- Reads are synchronous, with the same latency whatever the
  -- implementation, and the timing of ram_2p_r_w: with
  -- registered_output_c false, read_data_o holds the word at the
  -- read_address_i of the previous rising edge where read_en_i was
  -- asserted (one cycle of latency).  With registered_output_c true,
  -- the read port is a two-stage pipeline that advances on edges where
  -- read_en_i is asserted: with read_en_i always asserted, data comes
  -- two cycles after its address.  Deasserting read_en_i holds
  -- read_data_o.
  --
  -- A word written on an edge is read back from the next edge on.
  -- Reading, on the edge it is written, a word being written returns
  -- undefined data.
  --
  -- Storage is not initialized nor reset.
  component ram_auto is
    generic(
      addr_size_c: natural;
      word_size_c: positive := 8;
      data_word_count_c: positive := 1;
      registered_output_c: boolean := false;
      lutram_primitives_max_c: natural := ram_auto_lutram_primitives_max_c
      );
    port(
      clock_i: in std_ulogic;

      write_address_i: in unsigned(addr_size_c-1 downto 0);
      write_en_i: in std_ulogic_vector(data_word_count_c-1 downto 0);
      write_data_i: in std_ulogic_vector(data_word_count_c*word_size_c-1 downto 0);

      read_address_i: in unsigned(addr_size_c-1 downto 0);
      read_en_i: in std_ulogic := '1';
      read_data_o: out std_ulogic_vector(data_word_count_c*word_size_c-1 downto 0)
      );
  end component;

end package ram;

package body ram is

  function ram_auto_implementation(
    addr_size: natural;
    data_width: natural;
    lutram: nsl_hwconfig.memory_config.lutram_t;
    lutram_primitives_max: natural := ram_auto_lutram_primitives_max_c)
    return ram_implementation_t
  is
    variable primitives: natural;
  begin
    if not lutram.present or not lutram.async_read
      or lutram.depth = 0 or lutram.width = 0 then
      return RAM_IMPLEMENTATION_BLOCK;
    end if;

    primitives := ((2 ** addr_size + lutram.depth - 1) / lutram.depth)
                  * ((data_width + lutram.width - 1) / lutram.width);

    if primitives <= lutram_primitives_max then
      return RAM_IMPLEMENTATION_LUTRAM;
    end if;

    return RAM_IMPLEMENTATION_BLOCK;
  end function;

end package body ram;
