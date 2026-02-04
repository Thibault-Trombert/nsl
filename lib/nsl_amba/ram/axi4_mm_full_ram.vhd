library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory, nsl_logic, work, nsl_data;
use work.axi4_mm.all;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

entity axi4_mm_full_ram is
  generic(
    config_c : config_t;
    byte_size_l2_c : positive
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    axi_i : in master_t;
    axi_o : out slave_t
    );
end entity;

architecture beh of axi4_mm_full_ram is
    
  subtype ram_addr_t is unsigned(byte_size_l2_c-config_c.data_bus_width_l2-1 downto 0);
  subtype ram_strobe_t is std_ulogic_vector(0 to 2**config_c.data_bus_width_l2-1);
  subtype ram_data_t is std_ulogic_vector(0 to 8*ram_strobe_t'length-1);

  signal write_enable_s, read_enable_s: std_ulogic;
  signal write_address_s, read_address_s: ram_addr_t;
  signal write_strobe_s: ram_strobe_t;
  signal write_data_s, read_data_s: ram_data_t;

begin

  write_side: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_WRITING,
      ST_RESP
      );

    type regs_t is
    record
      state: state_t;
      transaction: transaction_t;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
      end if;
    end process;

    transition: process(r, axi_i) is
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;
          rin.transaction.valid <= '0';

        when ST_IDLE =>
          if is_valid(config_c, axi_i.aw) then
            rin.transaction <= transaction(config_c, axi_i.aw);
            rin.state <= ST_WRITING;
          end if;

        when ST_WRITING =>
          if is_valid(config_c, axi_i.w) then
            rin.transaction <= step(config_c, r.transaction);
            if is_last(config_c, r.transaction) then
              rin.state <= ST_RESP;
            end if;
          end if;

        when ST_RESP =>
          if is_ready(config_c, axi_i.b) then
            rin.state <= ST_IDLE;
          end if;
      end case;
    end process;

    write_address_s <= resize(address(config_c, r.transaction, config_c.data_bus_width_l2), write_address_s'length);
    write_enable_s <= to_logic(r.state = ST_WRITING and is_valid(config_c, axi_i.w));
    -- Our memory block handles words of M * N-bit data with M enable
    -- lines.  Strobe lines are in the same order as the data
    -- word.
    --
    -- If we take output if strb() in increasing order, we need byte
    -- from address 0 (modulo bus width) on the left of the data word,
    -- which maps to big endian.
    write_strobe_s <= strb(config_c, axi_i.w);
    write_data_s <= std_ulogic_vector(value(config_c, axi_i.w, ENDIAN_BIG));

    axi_o.aw.ready <= to_logic(r.state = ST_IDLE);
    axi_o.w.ready <= to_logic(r.state = ST_WRITING);
    axi_o.b <= write_response(config_c,
                              id => id(config_c, r.transaction),
                              user => user(config_c, r.transaction),
                              valid => r.state = ST_RESP,
                              resp => RESP_OKAY);
  end block;
  
  read_side: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_READ
      );

    subtype sideband_t is std_ulogic_vector(config_c.user_width
                                            + config_c.id_width
                                            + 1 - 1 downto 0);

    signal read_req_valid_s, read_req_ready_s : std_ulogic;
    signal read_req_addr_s : ram_addr_t;
    signal read_req_sideband_s, read_val_sideband_s : sideband_t;
    signal read_val_valid_s, read_val_ready_s : std_ulogic;
    signal read_val_data_s : ram_data_t;

    type regs_t is
    record
      state: state_t;
      transaction: transaction_t;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
      end if;
    end process;

    transition: process(r, axi_i, read_req_ready_s) is
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          if is_valid(config_c, axi_i.ar) then
            rin.transaction <= transaction(config_c, axi_i.ar);
            rin.state <= ST_READ;
          end if;

        when ST_READ =>
          if read_req_ready_s = '1' then
            rin.transaction <= step(config_c, r.transaction);
            if is_last(config_c, r.transaction) then
              rin.state <= ST_IDLE;
            end if;
          end if;
      end case;
    end process;

    moore: process(r) is
    begin
      read_req_valid_s <= '0';
      read_req_addr_s <= (others => '-');
      read_req_sideband_s <= (others => '-');

      axi_o.ar <= accept(config_c, false);

      case r.state is
        when ST_RESET =>
          null;

        when ST_IDLE =>
          axi_o.ar <= accept(config_c, true);
          
        when ST_READ =>
          read_req_valid_s <= '1';
          read_req_addr_s <= resize(address(config_c, r.transaction, config_c.data_bus_width_l2), read_req_addr_s'length);
          read_req_sideband_s <= user(config_c, r.transaction)
                                 & id(config_c, r.transaction)
                                 & to_logic(is_last(config_c, r.transaction));
      end case;            
    end process;

    axi_o.r <= read_data(config_c,
                         id => read_val_sideband_s(config_c.id_width downto 1),
                         value => unsigned(read_val_data_s),
                         endian => ENDIAN_BIG,
                         resp => RESP_OKAY,
                         user => read_val_sideband_s(read_val_sideband_s'left downto read_val_sideband_s'left - config_c.user_width + 1),
                         last => read_val_sideband_s(0) = '1',
                         valid => read_val_valid_s = '1');

    read_val_ready_s <= to_logic(is_ready(config_c, axi_i.r));

    streamer: nsl_memory.streamer.memory_streamer
      generic map(
        addr_width_c => ram_addr_t'length,
        data_width_c => 8 * ram_strobe_t'length,
        memory_latency_c => 1,
        sideband_width_c => read_req_sideband_s'length
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        addr_valid_i => read_req_valid_s,
        addr_ready_o => read_req_ready_s,
        addr_i => read_req_addr_s,
        sideband_i => read_req_sideband_s,

        data_valid_o => read_val_valid_s,
        data_ready_i => read_val_ready_s,
        data_o => read_val_data_s,
        sideband_o => read_val_sideband_s,

        mem_enable_o => read_enable_s,
        mem_address_o => read_address_s,
        mem_data_i => read_data_s
        );
  end block;
  
  fifo: nsl_memory.ram.ram_2p_homogeneous
    generic map(
      addr_size_c => ram_addr_t'length,
      word_size_c => 8,
      data_word_count_c => ram_strobe_t'length,
      registered_output_c => false,
      b_can_write_c => false
      )
    port map(
      a_clock_i => clock_i,

      a_enable_i => write_enable_s,
      a_address_i => write_address_s,
      a_data_i => write_data_s,
      a_write_en_i => write_strobe_s,

      b_clock_i => clock_i,

      b_enable_i => read_enable_s,
      b_address_i => read_address_s,
      b_data_o => read_data_s
      );
      
end architecture;
