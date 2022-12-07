library ieee;
use ieee.std_logic_1164.all;

entity ALUPipeControlGenerator is
    port (
        control_in: in std_logic_vector(5 downto 0);

        -- bit 1 and 0 are for mux 
        -- 00 - rb_data, 01 - leftshift(rb_data), 10 - se6(rb_data), 11 - invalid
        
        -- bit 3 and 2 are for alu operation same as in alu.vhdl
        -- 01 - add, 10 - nand, 11 - xor, 00 - invalid

        -- bit 4 is c_flag_enable for carry flag modification
        -- bit 5 is z_flag_enable for zero flag modification
        control_out: out std_logic_vector(5 downto 0);
    );
end entity ALUPipeControlGenerator;

architecture behavioural of ALUPipeControlGenerator is
    signal mux_select: std_logic_vector(1 downto 0) := (others => '0');
    signal alu_select: std_logic_vector(1 downto 0) := (others => '0');
    signal modify_carry, modify_zero: std_logic;
begin
    generate_mux_select_process: process(control_in)
    begin
        if (control_in(5 downto 2) = "0001" and control_in(1 downto 0) = "00") then
            -- ADD
            mux_select <= "00";
        elsif (control_in(5 downto 2) = "0001" and control_in(1 downto 0) = "10") then
            -- ADC
            mux_select <= "00";
        elsif (control_in(5 downto 2) = "0001" and control_in(1 downto 0) = "01") then
            -- ADZ
            mux_select <= "00";
        elsif (control_in(5 downto 2) = "0001" and control_in(1 downto 0) = "11") then
            -- ADL
            mux_select <= "01";
        elsif (control_in(5 downto 2) = "0000") then
            -- ADI
            mux_select <= "10";
        elsif (control_in(5 downto 2) = "0010") then
            -- NDU, NDC, NDZ
            mux_select <= "00";
        else 
            -- Default
            mux_select <= "00";
        end if;
    end process generate_mux_select_process;
end architecture behavioural;