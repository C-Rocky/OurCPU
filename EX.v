`include "lib/defines.vh"
module EX(                                                                      
    input wire clk,
    input wire rst,
    // input wire flush,
    input wire [`StallBus-1:0] stall,

    input wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,
    output wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus,
    output wire data_sram_en,
    output wire [3:0] data_sram_wen,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    output wire [`EX_TO_ID_WD-1:0] ex_to_id_bus,
    output wire stallreq_for_ex,
    output wire div_ready_to_id,
    //pre表示数据送给ID，来自当前ID前一条指令的信息
    output wire pre_inst_data_sram_en,
    output wire [3:0] pre_inst_data_sram_wen
);

    reg [`ID_TO_EX_WD-1:0] id_to_ex_bus_r;

    always @ (posedge clk) begin
        if (rst) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        end
        // else if (flush) begin
        //     id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        // end
        else if (stall[2]==`Stop && stall[3]==`NoStop) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        end
        else if (stall[2]==`NoStop) begin
            id_to_ex_bus_r <= id_to_ex_bus;
        end
    end

    wire [31:0] ex_pc, inst;
    wire [11:0] alu_op;
    wire [2:0] sel_alu_src1;
    wire [3:0] sel_alu_src2;
    wire data_ram_en;
    wire [3:0] data_ram_wen;
    wire [3:0] data_ram_readen;
    wire rf_we;
    wire [4:0] rf_waddr;
    wire sel_rf_res;
    wire [31:0] rf_rdata1, rf_rdata2;
    reg is_in_delayslot;

    wire [31:0] hi_out_file;         
    wire [31:0] lo_out_file;       
    wire hi_read; 
    wire lo_read; 
    wire hi_write;
    wire lo_write;
    wire w_lo_we;
    wire w_hi_we;
    wire [31:0] w_lo_i;
    wire [31:0] w_hi_i;
    wire is_lsa;

    assign {
        is_lsa,
        data_ram_readen,//230:227
        hi_read,        //226
        lo_read,        //225
        hi_write,       //224
        lo_write,       //223
        hi_out_file,    // 222:191
        lo_out_file,    // 190:159
        ex_pc,          // 158:127
        inst,           // 126:95
        alu_op,         // 94:83
        sel_alu_src1,   // 82:80
        sel_alu_src2,   // 79:76
        data_ram_en,    // 75
        data_ram_wen,   // 74:71
        rf_we,          // 70
        rf_waddr,       // 69:65
        sel_rf_res,     // 64
        rf_rdata1,         // 63:32 对应ID段的rs
        rf_rdata2          // 31:0 对应ID段的rt
    } = id_to_ex_bus_r;

    wire [31:0] imm_sign_extend, imm_zero_extend, sa_zero_extend;
    assign imm_sign_extend = {{16{inst[15]}},inst[15:0]};
    assign imm_zero_extend = {16'b0, inst[15:0]};
    assign sa_zero_extend = {27'b0,inst[10:6]};

    wire [31:0] alu_src1, alu_src2;
    wire [31:0] alu_result, ex_result;

    assign alu_src1 = sel_alu_src1[1] ? ex_pc :
                      sel_alu_src1[2] ? sa_zero_extend : rf_rdata1;

    assign alu_src2 = sel_alu_src2[1] ? imm_sign_extend :
                      sel_alu_src2[2] ? 32'd8 :
                      sel_alu_src2[3] ? imm_zero_extend : rf_rdata2;
    

    alu u_alu(
    	.alu_control (alu_op ),
        .alu_src1    (alu_src1    ),
        .alu_src2    (alu_src2    ),
        .alu_result  (alu_result  )
    );

    assign ex_result =  (hi_read) ?  hi_out_file :
                        (lo_read) ?  lo_out_file : alu_result;


       //新加的，和访存有有关
    assign data_sram_en = data_ram_en;
    assign data_sram_wen =   (data_ram_readen==4'b0101 && ex_result[1:0] == 2'b00 )? 4'b0001 
                            :(data_ram_readen==4'b0101 && ex_result[1:0] == 2'b01 )? 4'b0010
                            :(data_ram_readen==4'b0101 && ex_result[1:0] == 2'b10 )? 4'b0100
                            :(data_ram_readen==4'b0101 && ex_result[1:0] == 2'b11 )? 4'b1000
                            :(data_ram_readen==4'b0111 && ex_result[1:0] == 2'b00 )? 4'b0011
                            :(data_ram_readen==4'b0111 && ex_result[1:0] == 2'b10 )? 4'b1100
                            : data_ram_wen;//写使能信号  
    assign data_sram_addr = ex_result; //lw运算得到结果
    
    assign data_sram_wdata = data_sram_wen==4'b1111 ? rf_rdata2 
                            :data_sram_wen==4'b0001 ? {24'b0,rf_rdata2[7:0]}
                            :data_sram_wen==4'b0010 ? {16'b0,rf_rdata2[7:0],8'b0}
                            :data_sram_wen==4'b0100 ? {8'b0,rf_rdata2[7:0],16'b0}
                            :data_sram_wen==4'b1000 ? {rf_rdata2[7:0],24'b0}
                            :data_sram_wen==4'b0011 ? {16'b0,rf_rdata2[15:0]}
                            :data_sram_wen==4'b1100 ? {rf_rdata2[15:0],16'b0}
                            :32'b0;
    assign pre_inst_data_sram_en = data_ram_en;
    assign pre_inst_data_sram_wen = data_ram_wen; 
    
    // MUL part
    wire [63:0] mul_result;
    wire inst_mult, inst_multu;
    wire mul_ready_i;
    // wire mul_signed; // 有符号乘法标记
    // wire [31:0] mul_src1;
    // wire [31:0] mul_src2;
    reg stallreq_for_mul;
    assign inst_mult = (inst[31:26] == 6'b00_0000) & (inst[15:6] == 10'b00000_00000) & (inst[5:0] == 6'b01_1000);
    assign inst_multu = (inst[31:26] == 6'b00_0000) & (inst[15:6] == 10'b00000_00000) & (inst[5:0] == 6'b01_1001);

    // assign mul_signed = inst_mult;//判断有符号/无符号乘法
    // assign mul_src1 =(inst_mult | inst_multu) ? rf_rdata1 : 32'd0;
    // assign mul_src2 =(inst_mult | inst_multu) ? rf_rdata2 : 32'd0;
    reg [31:0] mul_opdata1_o;
    reg [31:0] mul_opdata2_o;
    reg mul_start_o;
    reg signed_mul_o;

    // mul u_mul(
    // 	.clk        (clk            ),
    //     .resetn     (~rst           ),
    //     .mul_signed (mul_signed     ),
    //     .ina        (mul_src1       ), // 乘法源操作数1
    //     .inb        (mul_src2       ), // 乘法源操作数2
    //     .result     (mul_result     ) // 乘法结果 64bit
    // );
    mul u_mul(
    	.rst          (rst          ),
        .clk          (clk          ),
        .signed_mul_i (signed_mul_o ),
        .opdata1_i    (mul_opdata1_o    ),
        .opdata2_i    (mul_opdata2_o    ),
        .start_i      (mul_start_o      ),
        .annul_i      (1'b0      ),
        .result_o     (mul_result     ), // 除法结果 64bit
        .ready_o      (mul_ready_i      )
    );
    
    // DIV part
    wire [63:0] div_result;
    wire inst_div, inst_divu;
    wire div_ready_i;
    reg stallreq_for_div;
    assign stallreq_for_ex = (stallreq_for_div && (div_ready_i==1'b0)) || (stallreq_for_mul && (mul_ready_i==1'b0));
    //WAIT
    assign div_ready_to_id = div_ready_i; 
    assign inst_div = (inst[31:26] == 6'b00_0000) & (inst[15:6] == 10'b00000_00000) & (inst[5:0] == 6'b01_1010);
    assign inst_divu = (inst[31:26] == 6'b00_0000) & (inst[15:6] == 10'b00000_00000) & (inst[5:0] == 6'b01_1011);

    reg [31:0] div_opdata1_o;
    reg [31:0] div_opdata2_o;
    reg div_start_o;
    reg signed_div_o;

    //div part
    div u_div(
    	.rst          (rst          ),
        .clk          (clk          ),
        .signed_div_i (signed_div_o ),
        .opdata1_i    (div_opdata1_o    ),
        .opdata2_i    (div_opdata2_o    ),
        .start_i      (div_start_o      ),
        .annul_i      (1'b0      ),
        .result_o     (div_result     ), // 除法结果 64bit
        .ready_o      (div_ready_i      )
    );

    always @ (*) begin
        if (rst) begin
            stallreq_for_mul = `NoStop;
            mul_opdata1_o = `ZeroWord;
            mul_opdata2_o = `ZeroWord;
            mul_start_o = `MulStop;
            signed_mul_o = 1'b0;
        end
        else begin
            stallreq_for_mul = `NoStop;
            mul_opdata1_o = `ZeroWord;
            mul_opdata2_o = `ZeroWord;
            mul_start_o = `MulStop;
            signed_mul_o = 1'b0;
            case ({inst_mult,inst_multu})
                2'b10:begin
                    if (mul_ready_i == `MulResultNotReady) begin
                        mul_opdata1_o = rf_rdata1;
                        mul_opdata2_o = rf_rdata2;
                        mul_start_o = `MulStart;
                        signed_mul_o = 1'b1;
                        stallreq_for_mul = `Stop;
                    end
                    else if (mul_ready_i == `MulResultReady) begin
                        mul_opdata1_o = rf_rdata1;
                        mul_opdata2_o = rf_rdata2;
                        mul_start_o = `MulStop;
                        signed_mul_o = 1'b1;
                        stallreq_for_mul = `NoStop;
                    end
                    else begin
                        mul_opdata1_o = `ZeroWord;
                        mul_opdata2_o = `ZeroWord;
                        mul_start_o = `MulStop;
                        signed_mul_o = 1'b0;
                        stallreq_for_mul = `NoStop;
                    end
                end
                2'b01:begin
                    if (mul_ready_i == `MulResultNotReady) begin
                        mul_opdata1_o = rf_rdata1;
                        mul_opdata2_o = rf_rdata2;
                        mul_start_o = `MulStart;
                        signed_mul_o = 1'b0;
                        stallreq_for_mul = `Stop;
                    end
                    else if (mul_ready_i == `MulResultReady) begin
                        mul_opdata1_o = rf_rdata1;
                        mul_opdata2_o = rf_rdata2;
                        mul_start_o = `MulStop;
                        signed_mul_o = 1'b0;
                        stallreq_for_mul = `NoStop;
                    end
                    else begin
                        mul_opdata1_o = `ZeroWord;
                        mul_opdata2_o = `ZeroWord;
                        mul_start_o = `MulStop;
                        signed_mul_o = 1'b0;
                        stallreq_for_mul = `NoStop;
                    end
                end
                default:begin
                end
            endcase
        end
    end

    always @ (*) begin
        if (rst) begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
        end
        else begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
            case ({inst_div,inst_divu})
                2'b10:begin
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                2'b01:begin
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                default:begin
                end
            endcase
        end
    end
    wire inst_mthi;
    wire inst_mtlo;
    assign inst_mthi    = (inst[31:26]==6'b00_0000)&(inst[20:6]==15'b00000_00000_00000)&(inst[5:0]==6'b01_0001);
    assign inst_mtlo    = (inst[31:26]==6'b00_0000)&(inst[20:6]==15'b00000_00000_00000)&(inst[5:0]==6'b01_0011);
    assign w_hi_we = inst_mult | inst_multu | inst_div | inst_divu | inst_mthi;
    assign w_lo_we = inst_mult | inst_multu | inst_div | inst_divu | inst_mtlo;
    assign w_hi_i = (inst_mult | inst_multu) ?  mul_result[63:32] :
                    (inst_div | inst_divu ) ? div_result[63:32] : 
                    (hi_write) ? rf_rdata1:32'b0;
    assign w_lo_i = (inst_mult | inst_multu) ?  mul_result[31:0] :
                    (inst_div | inst_divu ) ? div_result[31:0] :
                    (lo_write) ? rf_rdata1 : 32'b0;
    assign ex_to_mem_bus = {
        data_ram_readen,//145:142
        w_hi_we,        // 141
        w_hi_i,         // 140:109
        w_lo_we,        // 108
        w_lo_i,         // 107:76
        ex_pc,          // 75:44
        data_ram_en,    // 43
        data_ram_wen,   // 42:39
        sel_rf_res,     // 38
        rf_we,          // 37
        rf_waddr,       // 36:32
        ex_result       // 31:0
    };

    assign ex_to_id_bus = {
        w_hi_we,        // 103
        w_hi_i,         // 102:71
        w_lo_we,        // 70
        w_lo_i,         // 69:38
        rf_we,          // 37
        rf_waddr,       // 36:32
        ex_result       // 31:0
    };
endmodule