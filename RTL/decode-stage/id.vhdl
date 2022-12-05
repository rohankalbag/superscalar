library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity IDStage is
    port(
        -- INPUTS
        clr: in std_logic;
        clk: in std_logic;
        IFID_inc_Op, IFID_PC_Op: in std_logic_vector(15 downto 0);
		IFID_IMem_Op: in std_logic_vector(31 downto 0);
        -- Will need to add more inputs to handle forwarding logic

        -- OUTPUTS
        wr_inst1, wr_inst2: out std_logic; -- write bits for newly decoded instructions 
        wr_ALU1, wr_ALU2: out std_logic; -- write bits for newly executed instructions
        rd_ALU1, rd_ALU2: out std_logic;  -- read bits for issuing ready instructions
		control_inst1, control_inst2: out std_logic_vector(5 downto 0); -- control values for the two instructions
        pc_inst1, pc_inst2: out std_logic_vector(15 downto 0); -- pc values for the two instructions
        opr1_inst1, opr2_inst1, opr1_inst2, opr2_inst2: out std_logic_vector(15 downto 0); -- operand values for the two instructions
        imm6_inst1, imm6_inst2: out std_logic_vector(5 downto 0); -- imm6 values for the two instructions
        c_inst1, z_inst1, c_inst2, z_inst2: out std_logic_vector(7 downto 0); -- carry and zero values for the two instructions
        valid1_inst1, valid2_inst1, valid3_inst1, valid4_inst1: out std_logic; -- valid bits for first instruction
        valid1_inst2, valid2_inst2, valid3_inst2, valid4_inst2: out std_logic; -- valid bits for second instruction
        data_ALU1, data_ALU2: out std_logic_vector(15 downto 0); -- data forwarded from the execution pipelines
        rr1_ALU1, rr1_ALU2, rr2_ALU1, rr2_ALU2, rr3_ALU1, rr3_ALU2: out std_logic_vector(7 downto 0); -- rr values coming from the ROB corresponding to execution pipeline outputs
        c_ALU1_in, z_ALU1_in, c_ALU2_in, z_ALU2_in: out std_logic; -- carry and zero values forwarded from the execution pipelines
        finished_ALU1, finished_ALU2: out std_logic -- finished bits coming from the execution pipelines
    );
end entity IDStage;

architecture behavioural of IDStage is
    component DataRegisterFile is 
        port(
            clk, clr: in std_logic;
            source_select_1, source_select_2, source_select_3, source_select_4: in std_logic_vector(2 downto 0);

            dest_select_1, dest_select_2: in std_logic_vector(2 downto 0);
            tag_1, tag_2: in std_logic_vector(7 downto 0);

            wr1, wr2: in std_logic;
            finish_alu_1, finish_alu_2: in std_logic;
            rr_alu_1, rr_alu_2: in std_logic_vector(7 downto 0);
            data_alu_1, data_alu_2: in std_logic_vector(15 downto 0);

            complete: in std_logic;
            inst_complete_dest: in std_logic_vector(2 downto 0);

            data_out_1, data_out_2, data_out_3, data_out_4: out std_logic_vector(15 downto 0);
            data_tag_1, data_tag_2, data_tag_3, data_tag_4: out std_logic;

            rrf_busy_out: out std_logic_vector((integer'(2)**8)-1 downto 0)
        );
    end component;

    component FlagRegisterFile is 
        port(
            clk, clr: in std_logic;

            wr1, wr2: in std_logic;
            tag_1, tag_2: in std_logic_vector(7 downto 0);

            finish_alu_1, finish_alu_2: in std_logic;
            rr_alu_1, rr_alu_2: in std_logic_vector(7 downto 0);
            data_alu_1, data_alu_2: in std_logic_vector(0 downto 0);

            complete: in std_logic;

            data_out_1, data_out_2: out std_logic_vector(7 downto 0);
            data_tag_1, data_tag_2: out std_logic;

            rrf_busy_out: out std_logic_vector((integer'(2)**8)-1 downto 0)
        );
    end component;

    component DualPriorityEncoder is
        generic (
            input_width : integer := 2 ** 8;
            output_width : integer := 8
        );
        port (
            a: in std_logic_vector(input_width - 1 downto 0);
            y_first: out std_logic_vector(output_width - 1 downto 0);
            valid_first: out std_logic;
            y_second: out std_logic_vector(output_width - 1 downto 0);
            valid_second: out std_logic
        );
    end component;
    
    component OperandExtractor is
        port(
            instruction: std_logic_vector(15 downto 0);

            operand1, operand2: std_logic_vector(2 downto 0);
            destination: std_logic_vector(2 downto 0)
        );
    end component;

    component DestinationWriteChecker is
        port(
            instruction: in std_logic_vector(15 downto 0);
            dest_write: out std_logic
        );
    end component;

    signal wr_inst1_sig, wr_inst2_sig: std_logic := '1';
    signal wr_ALU1_sig, wr_ALU2_sig: std_logic := '1';

    signal opr_addr1_inst1, opr_addr2_inst1, opr_addr1_inst2, opr_addr2_inst2: std_logic_vector(2 downto 0) := (others => '0');
    signal dest_addr_inst1, dest_addr_inst2: std_logic_vector(2 downto 0) := (others => '0'); 

    signal data_rrf_busy, carry_rrf_busy, zero_rrf_busy: std_logic_vector((integer'(2)**8)-1 downto 0) := (others => '0');

    -- Signals _rf_full_first, _rf_full_second can be used to check if the corresponding RF have space
    signal data_rr_tag_inst1, data_rr_tag_inst2: std_logic_vector(7 downto 0) := (others => '0');
    signal data_rf_full_first, data_rf_full_second: std_logic;

    signal carry_rr_tag_inst1, carry_rr_tag_inst2: std_logic_vector(7 downto 0) := (others => '0');
    signal carry_rf_full_first, carry_rf_full_second: std_logic;

    signal zero_rr_tag_inst1, zero_rr_tag_inst2: std_logic_vector(7 downto 0) := (others => '0');
    signal zero_rf_full_first, zero_rf_full_second: std_logic;

    signal data_reg_wr1, data_reg_wr2: std_logic;
begin
    -- Control logic for wr_inst1, wr_inst2 (if the RS is full, we cannot write into it). For the time being,
    -- we assume that the RS is large enough so no capacity stalls occur
    instruction_write_control_process: process(wr_inst1_sig, wr_inst2_sig)
    begin
        wr_inst1_sig <= '1';
        wr_inst2_sig <= '1';
    end process instruction_write_control_process;

    wr_inst1 <= wr_inst1_sig;
    wr_inst2 <= wr_inst2_sig;
    --

    -- TODO 
    alu_write_control_process: process(wr_ALU1_sig, wr_ALU2_sig)
    begin

    end process alu_write_control_process;

    wr_ALU1 <= wr_ALU1_sig;
    wr_ALU2 <= wr_ALU2_sig;
    --

    -- Opcode + last two bits for each instruction
    control_inst1 <= IFID_IMem_Op(31 downto 28) & IFID_IMem_Op(17 downto 16);
    control_inst2 <= IFID_IMem_Op(15 downto 12) & IFID_IMem_Op(1 downto 0);
    -- 

    -- PC for both instructions
    pc_inst1 <= IFID_PC_Op;
    pc_inst2 <= IFID_inc_Op;
    --

    -- Immediate data field
    imm6_inst1 <= IFID_IMem_Op(21 downto 16);
    imm6_inst2 <= IFID_IMem_Op(5 downto 0);
    -- 

    inst1_operands: OperandExtractor
        port map(
            instruction => IFID_IMem_Op(31 downto 16),

            operand1 => opr_addr1_inst1,
            operand2 => opr_addr2_inst1,
            destination => dest_addr_inst1
        );

    inst2_operands: OperandExtractor
        port map(
            instruction => IFID_IMem_Op(15 downto 0),

            operand1 => opr_addr1_inst2,
            operand2 => opr_addr2_inst2,
            destination => dest_addr_inst2
        );

    data_priority_encoder: DualPriorityEncoder
        generic map (
            input_width => 2 ** 8;
            output_width => 8
        )
        port map(
            a => data_rrf_busy,
            y_first => data_rr_tag_inst1,
            valid_first => data_rf_full_first,
            y_second => data_rr_tag_inst2,
            valid_second => data_rf_full_second
        );

    dest_write_checker_inst1: DestinationWriteChecker
        port map(
            instruction => IFID_IMem_Op(31 downto 16),
            dest_write => data_reg_wr1
        );
    
    dest_write_checker_inst2: DestinationWriteChecker
        port map(
            instruction => IFID_IMem_Op(15 downto 0),
            dest_write => data_reg_wr2
        );

    data_register_file: DataRegisterFile
        port map(
            clk => clk,
            clr => clr,

            source_select_1 => opr_addr1_inst1,
            source_select_2 => opr_addr2_inst1,
            source_select_3 => opr_addr1_inst2,
            source_select_4 => opr_addr2_inst2,

            wr1 => data_reg_wr1, 
            wr2 => data_reg_wr2,
            dest_select_1 => dest_addr_inst1,
            dest_select_2 => dest_addr_inst2,
            tag_1 => data_rr_tag_inst1, 
            tag_2 => data_rr_tag_inst2,
            
            finish_alu_1 =>, 
            finish_alu_2 =>,
            rr_alu_1 =>, 
            rr_alu_2 =>,
            data_alu_1 =>, 
            data_alu_2 =>,

            complete =>,
            inst_complete_dest =>,

            data_out_1 => opr1_inst1,
            data_out_2 => opr2_inst1,
            data_out_3 => opr1_inst2,
            data_out_4 => opr2_inst2,

            data_tag_1 => valid1_inst1,
            data_tag_2 => valid2_inst1,
            data_tag_3 => valid1_inst2,
            data_tag_4 => valid2_inst2,

            rrf_busy_out => data_rrf_busy
        );

    carry_priority_encoder: DualPriorityEncoder
        generic map (
            input_width => 2 ** 8;
            output_width => 8
        )
        port map(
            a => carry_rrf_busy,
            y_first => carry_rr_tag_inst1,
            valid_first => carry_rf_full_first,
            y_second => carry_rr_tag_inst2,
            valid_second => carry_rf_full_second
        );

    carry_register_file: FlagRegisterFile
        port map(
            clk => clk, 
            clr => clr,

            wr1 =>, 
            wr2 =>,
            tag_1 => carry_rr_tag_inst1,
            tag_2 => carry_rr_tag_inst2,

            finish_alu_1 =>,
            finish_alu_2 =>,
            rr_alu_1 =>, 
            rr_alu_2 =>,
            data_alu_1 =>,
            data_alu_2 =>,

            complete =>,

            data_out_1 => c_inst1, 
            data_out_2 => c_inst2,
            
            data_tag_1 => valid3_inst1, 
            data_tag_2 => valid3_inst2,

            rrf_busy_out => carry_rrf_busy
        );

    zero_priority_encoder: DualPriorityEncoder
        generic map (
            input_width => 2 ** 8;
            output_width => 8
        )
        port map(
            a => zero_rrf_busy,
            y_first => zero_rr_tag_inst1,
            valid_first => zero_rf_full_first,
            y_second => zero_rr_tag_inst2,
            valid_second => zero_rf_full_second
        );

    flag_register_file: FlagRegisterFile
        port map(
            clk => clk, 
            clr => clr,

            wr1 =>, 
            wr2 =>,
            tag_1 => zero_rr_tag_inst1,
            tag_2 => zero_rr_tag_inst2,

            finish_alu_1 =>,
            finish_alu_2 =>,
            rr_alu_1 =>, 
            rr_alu_2 =>,
            data_alu_1 =>,
            data_alu_2 =>,

            complete =>,

            data_out_1 => z_inst1, 
            data_out_2 => z_inst2,
            
            data_tag_1 => valid4_inst1, 
            data_tag_2 => valid4_inst2,

            rrf_busy_out => zero_rrf_busy
        );

end architecture behavioural;