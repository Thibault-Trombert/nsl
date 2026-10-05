library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c, nsl_bnoc, nsl_data, nsl_math;

-- I2C bys master transactor that takes command stream from a framed interface.
package transactor is

  -- CMD: [READ | n-1]
  -- RSP: [Data * n]
  constant I2C_CMD_READ      : nsl_bnoc.framed.framed_data_t := "1-------";
  constant I2C_CMD_READ_ACK  : nsl_bnoc.framed.framed_data_t := "11------";
  constant I2C_CMD_READ_NACK : nsl_bnoc.framed.framed_data_t := "10------";
  -- CMD: [WRITE | n-1, Data * n]
  -- RSP: [Ack * n]
  constant I2C_CMD_WRITE     : nsl_bnoc.framed.framed_data_t := "01------";
  -- CMD: [DIV | n-1]
  -- RSP: [00]
  constant I2C_CMD_DIV       : nsl_bnoc.framed.framed_data_t := "000-----";

  -- Divisor command argument giving the fastest SCL rate not above
  -- scl_hz, for a transactor running at clock_i_hz.  Divisor 0 runs
  -- SCL between 500kHz and 1MHz, divisor d divides that by d + 1.
  -- Saturates at the slowest rate a divisor command can state.
  function scl_divisor(clock_i_hz, scl_hz: positive) return unsigned;
  -- CMD: [START]
  -- RSP: [00 or ff]
  constant I2C_CMD_START     : nsl_bnoc.framed.framed_data_t := "00100000";
  -- CMD: [STOP]
  -- RSP: [00 or ff]
  constant I2C_CMD_STOP      : nsl_bnoc.framed.framed_data_t := "00100001";

  component transactor_framed_controller
    generic(
      clock_i_hz_c : natural;
      -- Number of SCL half-cycles a device may stretch the clock (or
      -- otherwise hold a line) before the current command is aborted.
      stuck_timeout_half_cycles_c : natural := 8
      );
    port(
      clock_i    : in std_ulogic;
      reset_n_i : in std_ulogic;

      i2c_o  : out nsl_i2c.i2c.i2c_o;
      i2c_i  : in  nsl_i2c.i2c.i2c_i;

      cmd_i   : in nsl_bnoc.framed.framed_req;
      cmd_o   : out nsl_bnoc.framed.framed_ack;
      rsp_o  : out nsl_bnoc.framed.framed_req;
      rsp_i  : in nsl_bnoc.framed.framed_ack
      );
  end component;

  component framed_addressed_controller
    generic(
      addr_byte_count_c : natural;
      big_endian_c : boolean;
      txn_byte_count_max_c : positive
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      cmd_i  : in nsl_bnoc.framed.framed_ack;
      cmd_o  : out nsl_bnoc.framed.framed_req;
      rsp_o  : out nsl_bnoc.framed.framed_ack;
      rsp_i  : in nsl_bnoc.framed.framed_req;

      valid_i : in std_ulogic;
      ready_o : out std_ulogic;
      -- When set, every transaction starts with a divisor command
      -- carrying divisor_i, so it runs at its own SCL rate whatever
      -- the transactor ran before.  Left unset, the transactor rate
      -- is left untouched.  Pseudo-constant.
      set_divisor_i : in std_ulogic := '0';
      divisor_i : in unsigned(4 downto 0) := (others => '0');
      saddr_i : in unsigned(7 downto 1);
      addr_i : in unsigned(8 * addr_byte_count_c - 1 downto 0) := (others => '0');
      write_i : in std_ulogic;
      wdata_i : in nsl_data.bytestream.byte_string(0 to txn_byte_count_max_c-1);
      data_byte_count_i : in natural range 1 to txn_byte_count_max_c;

      valid_o : out std_ulogic;
      ready_i : in std_ulogic;
      rdata_o : out nsl_data.bytestream.byte_string(0 to txn_byte_count_max_c-1);
      error_o : out std_ulogic
      );
  end component;
  
end package transactor;

package body transactor is

  function scl_divisor(clock_i_hz, scl_hz: positive) return unsigned
  is
    -- SCL half cycle at divisor 0, as the transactor counts it
    constant half_cycle_c: positive
      := 2 ** (nsl_math.arith.log2(clock_i_hz / 1e6) - 1);
    constant ratio_c: positive
      := (clock_i_hz + 2 * half_cycle_c * scl_hz - 1) / (2 * half_cycle_c * scl_hz);
  begin
    return to_unsigned(nsl_math.arith.min(ratio_c - 1, 31), 5);
  end function;

end package body transactor;
