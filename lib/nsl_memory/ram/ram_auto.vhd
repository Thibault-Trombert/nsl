library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory, nsl_hwconfig;
use nsl_memory.ram.all;

entity ram_auto is
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
end entity;

-- The LUT RAM implementation is an array written synchronously and read
-- asynchronously, the read registered once (or twice) to give the
-- block RAM's latency.  The asynchronous read port is what LUT RAM
-- offers and block RAM does not, so synthesizers map the array to LUT
-- RAM without being told.
architecture beh of ram_auto is

  constant implementation_c: ram_implementation_t
    := ram_auto_implementation(addr_size_c, data_word_count_c * word_size_c,
                               nsl_hwconfig.memory_config.lutram,
                               lutram_primitives_max_c);

  subtype word_t is std_ulogic_vector(data_word_count_c*word_size_c-1 downto 0);

begin

  block_ram: if implementation_c = RAM_IMPLEMENTATION_BLOCK
  generate
    signal write_enable_s: std_ulogic;
  begin
    write_enable_s <= '1' when write_en_i /= (write_en_i'range => '0') else '0';

    impl: nsl_memory.ram.ram_2p_homogeneous
      generic map(
        addr_size_c => addr_size_c,
        word_size_c => word_size_c,
        data_word_count_c => data_word_count_c,
        registered_output_c => registered_output_c,
        b_can_write_c => false
        )
      port map(
        a_clock_i => clock_i,
        a_enable_i => write_enable_s,
        a_write_en_i => write_en_i,
        a_address_i => write_address_i,
        a_data_i => write_data_i,
        a_data_o => open,

        b_clock_i => clock_i,
        b_enable_i => read_en_i,
        b_address_i => read_address_i,
        b_data_o => read_data_o
        );
  end generate;

  lut_ram: if implementation_c = RAM_IMPLEMENTATION_LUTRAM
  generate
    type word_vector_t is array(natural range <>) of word_t;
    signal storage: word_vector_t(0 to 2**addr_size_c-1);
    signal read_s, out_reg_s: word_t;
  begin
    write_port: process(clock_i) is
    begin
      if rising_edge(clock_i) then
        for i in 0 to data_word_count_c-1
        loop
          if write_en_i(i) = '1' then
            storage(to_integer(to_01(write_address_i, '0')))((i+1)*word_size_c-1 downto i*word_size_c)
              <= write_data_i((i+1)*word_size_c-1 downto i*word_size_c);
          end if;
        end loop;
      end if;
    end process;

    read_s <= storage(to_integer(to_01(read_address_i, '0')));

    read_port: process(clock_i) is
    begin
      if rising_edge(clock_i) then
        if read_en_i = '1' then
          if registered_output_c then
            out_reg_s <= read_s;
            read_data_o <= out_reg_s;
          else
            read_data_o <= read_s;
          end if;
        end if;
      end if;
    end process;
  end generate;

end architecture;
