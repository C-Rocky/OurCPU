`include "lib/defines.vh"
module ID(
    input wire clk,
    input wire rst,
    // input wire flush,
    input wire [`StallBus-1:0] stall,
    
    output wire stallreq_for_id,

    input wire [`IF_TO_ID_WD-1:0] if_to_id_bus,
    
    input wire [31:0] inst_sram_rdata,
    
    input wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus,
    
    input wire [`WB_TO_ID_WD-1:0] wb_to_id_bus,
   
    output wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,
  
    output wire [`BR_WD-1:0] br_bus,
    
    input wire [`EX_TO_ID_WD-1:0] ex_to_id_bus,
    
    input wire [`MEM_TO_ID_WD-1:0] mem_to_id_bus,

    input wire div_ready_to_id,
    
    input wire pre_inst_data_sram_en,

    input wire [3:0] pre_inst_data_sram_wen
   
);

    reg [`IF_TO_ID_WD-1:0] if_to_id_bus_r;
    wire [31:0] inst;
    wire [31:0] id_pc;
    wire ce;

    wire w_hi_we;    
    wire [31:0] w_hi_i;     
    wire w_lo_we;    
    wire [31:0]w_lo_i;
    wire wb_rf_we;
    wire [4:0] wb_rf_waddr;
    wire [31:0] wb_rf_wdata;

    wire [31:0] hi_out_file;        
    wire [31:0] lo_out_file;

    wire is_lsa;


    //wire aa_en;
    //wire [31:0] aa_inst;
//    wire aaa;
//    wire bbb;
//    wire [31:0]ccc;
//    wire [31:0]ddd;


    //为了保证PC和inst同步，使用inst_reg在出现load读写冲突时储存指令
    //assign inst = inst_sram_rdata;
    //inst暂存器
    reg [31:0] inst_reg;
    reg inst_reg_en;
    always @ (posedge clk) begin
        inst_reg_en <= 1'b0;
        if (rst) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;        
        end
        // else if (flush) begin
        //     ic_to_id_bus <= `IC_TO_ID_WD'b0;
        // end
        else if (stall[1]==`Stop && stall[2]==`NoStop) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        end
        else if (stall[1]==`NoStop) begin
            if_to_id_bus_r <= if_to_id_bus;
        end
    end
    
    
    //保证inst和PC同步，inst_reg_en为1，则表示inst_reg里面的需要用
    always @ (posedge clk) begin
        //if(stall[2]==`Stop && ==div_ready_to_id1'b0)begin
        if(stall[2]==`Stop)begin
             inst_reg <= inst;
             inst_reg_en <= 1'b1;
        end
        else begin
            inst_reg <= 32'b0;
            inst_reg_en <= 1'b0;
        end
    end

    // always @ (stallreq_for_id) begin
    //     inst_reg <= inst;
    //     inst_reg_en <= 1'b1;
    // end
    //为了保证PC和inst同步，使用inst_reg在出现load读写冲突时储存指令
    //assign inst = inst_sram_rdata;
    //inst暂存器 这个定义放上面了
    // reg [31:0] inst_reg;
    // reg inst_reg_en;
    assign inst = (inst_reg_en == 1'b0) ? inst_sram_rdata  : inst_reg;
//      (stall[2]==1'b1 && div_ready_to_id==1'b0) ? ex_id_div_inst
    assign {
        ce,
        id_pc
    } = if_to_id_bus_r;  

    assign {
        w_hi_we,    
        w_hi_i,     
        w_lo_we,    
        w_lo_i,
        wb_rf_we,
        wb_rf_waddr,
        wb_rf_wdata
    } = wb_to_rf_bus;
    wire pre_ex_w_hi_we;        
    wire [31:0] pre_ex_w_hi_i;        
    wire pre_ex_w_lo_we;        
    wire [31:0] pre_ex_w_lo_i; 
    wire pre_ex_to_id_we;
    wire [4:0] pre_ex_to_id_waddr;
    wire [31:0] pre_ex_result;
    wire [103:0] ex_to_regfile_bus;

    assign {
        pre_ex_w_hi_we,        // 103
        pre_ex_w_hi_i,         // 102:71
        pre_ex_w_lo_we,        // 70
        pre_ex_w_lo_i,         // 69:38  
        pre_ex_to_id_we,          // 37
        pre_ex_to_id_waddr,       // 36:32
        pre_ex_result       // 31:0
    } =  ex_to_id_bus; //主要用前两条判断是否上一条指令在进行load或store操作
    assign ex_to_regfile_bus ={
        pre_ex_w_hi_we,        // 103
        pre_ex_w_hi_i,         // 102:71
        pre_ex_w_lo_we,        // 70
        pre_ex_w_lo_i,         // 69:38  
        pre_ex_to_id_we,          // 37
        pre_ex_to_id_waddr,       // 36:32
        pre_ex_result       // 31:0
    } ; //主要用前两条判断是否上一条指令在进行load或store操作

    wire [5:0] opcode;
    wire [4:0] rs,rt,rd,sa;
    wire [5:0] func;
    wire [15:0] imm;
    wire [25:0] instr_index;
    wire [19:0] code;
    wire [4:0] base;
    wire [15:0] offset;
    wire [2:0] sel;

    wire [63:0] op_d, func_d;
    wire [31:0] rs_d, rt_d, rd_d, sa_d;

    wire [2:0] sel_alu_src1;
    wire [3:0] sel_alu_src2;
    wire [11:0] alu_op;

    wire data_ram_en;
    wire [3:0] data_ram_wen;
    wire [3:0] data_ram_readen;
    
    wire rf_we;
    wire [4:0] rf_waddr;
    wire sel_rf_res;
    wire [2:0] sel_rf_dst;

    wire [31:0] rdata1, rdata2;
    wire hi_read; 
    wire lo_read; 
    wire hi_write;
    wire lo_write;

    regfile u_regfile(
    	.clk    (clk    ),
    	.ex_to_regfile_bus(ex_to_regfile_bus),
    	.mem_to_id_bus(mem_to_id_bus),
        .wb_to_id_bus(wb_to_id_bus),
        .raddr1 (rs ),
        .rdata1 (rdata1 ),
        .raddr2 (rt ),
        .rdata2 (rdata2 ),
        //常规hilo
        .w_hi_we(w_hi_we),           
        .w_lo_we(w_lo_we),           
        .w_hi_i(w_hi_i),                
        .w_lo_i(w_lo_i),
        .hi_read(hi_read),
        .lo_read(lo_read),
        .hi_out_file(hi_out_file),
        .lo_out_file(lo_out_file),
        .we     (wb_rf_we     ),
        .waddr  (wb_rf_waddr  ),
        .wdata  (wb_rf_wdata  )
    );

    assign opcode = inst[31:26];
    assign rs = inst[25:21];
    assign rt = inst[20:16];
    assign rd = inst[15:11];
    assign sa = inst[10:6];
    assign func = inst[5:0];
    assign imm = inst[15:0];
    assign instr_index = inst[25:0];
    assign code = inst[25:6];
    assign base = inst[25:21];
    assign offset = inst[15:0];
    assign sel = inst[2:0];

    wire inst_ori, inst_lui, inst_addiu, inst_addu, inst_beq, inst_jr,inst_jal, inst_subu, inst_sll;
    wire inst_and, inst_or, inst_lw, inst_sw, inst_xor,inst_andi,inst_nor,inst_xori,inst_sllv,inst_sra,inst_srav;
    wire inst_sltu,inst_bne,inst_slt,inst_slti,inst_sltiu,inst_j,inst_srlv,inst_srl,inst_bgtz,inst_add;
    wire inst_movn,inst_movz,inst_mfhi,inst_mflo,inst_mthi,inst_mtlo;  
    wire inst_div, inst_divu, inst_mult, inst_multu;
    wire inst_bgez,inst_blez,inst_bltz,inst_bltzal,inst_bgezal,inst_jalr;
    wire op_add, op_sub, op_slt, op_sltu;
    wire op_and, op_nor, op_or, op_xor;
    wire op_sll, op_srl, op_sra, op_lui;
    wire inst_lb,inst_lbu, inst_lh, inst_lhu, inst_sb,  inst_sh;
    wire inst_lsa;

    decoder_6_64 u0_decoder_6_64(
    	.in  (opcode  ),
        .out (op_d )
    );

    decoder_6_64 u1_decoder_6_64(
    	.in  (func  ),
        .out (func_d )
    );
    
    decoder_5_32 u0_decoder_5_32(
    	.in  (rs  ),
        .out (rs_d )
    );

    decoder_5_32 u1_decoder_5_32(
    	.in  (rt  ),
        .out (rt_d )
    );
    
    decoder_5_32 u2_decoder_5_32(
    	.in  (sa  ),
        .out (sa_d )
    );

    
    assign inst_ori     = op_d[6'b00_1101];
    assign inst_lui     = op_d[6'b00_1111] & (rs == 5'b0_0000);
    //assign inst_lui     = op_d[6'b00_1111];
    assign inst_addiu   = op_d[6'b00_1001];
    assign inst_beq     = op_d[6'b00_0100];
    assign inst_subu    = op_d[6'b00_0000] & func_d[6'b10_0011] & (sa == 5'b0_0000);
    assign inst_jr      = op_d[6'b00_0000] & (inst[20:11] == 10'b0_000000000) & (sa == 5'b0_0000) & (func == 6'b00_1000);
    assign inst_jalr     = op_d[6'b00_0000] & (rt == 5'b0_0000) & (sa == 5'b0_0000) & (func == 6'b00_1001);
    assign inst_jal     = op_d[6'b00_0011];
    assign inst_addu    = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b10_0001);
    assign inst_sll = op_d[6'b00_0000] & (rs == 5'b0_0000) & (func == 6'b00_0000);
    assign inst_or = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b10_0101);
    assign inst_lw = op_d[6'b10_0011];
    assign inst_sw = op_d[6'b10_1011];
    assign inst_xor = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b10_0110);
    assign inst_and = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b10_0100);
    assign inst_sltu = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b10_1011);
    assign inst_bne = op_d[6'b00_0101];
    assign inst_slt = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b10_1010);
    assign inst_slti = op_d[6'b00_1010];
    assign inst_sltiu = op_d[6'b00_1011];
    assign inst_j = op_d[6'b00_0010];
    assign inst_srlv = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b00_0110);
    assign inst_srl = op_d[6'b00_0000] & (rs == 5'b0_0000) & (func == 6'b00_0010);
    assign inst_bgtz = op_d[6'b00_0111] & (rt == 5'b0_0000);
    assign inst_bgez = op_d[6'b00_0001] & (rt == 5'b0_0001);
    assign inst_add = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b10_0000);
    assign inst_addi = op_d[6'b00_1000];
    assign inst_sub = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b10_0010);
    assign inst_andi= op_d[6'b00_1100];
    assign inst_xori= op_d[6'b00_1110];
    assign  inst_nor = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b10_0111);
    assign inst_sllv = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b00_0100);
    assign inst_sra = op_d[6'b00_0000] & (rs == 5'b0_0000) & (func == 6'b00_0011);
    assign inst_srav = op_d[6'b00_0000] & (sa == 5'b0_0000) & (func == 6'b00_0111);
    assign inst_blez = op_d[6'b00_0110] & (rt == 5'b00000);
    assign inst_bltz = op_d[6'b00_0001] & (rt == 5'b00000);
    assign inst_bltzal = op_d[6'b00_0001] & (rt == 5'b10000);
    assign inst_bgezal = op_d[6'b00_0001] & (rt == 5'b10001);
    
    assign inst_movn    = op_d[6'b00_0000]&(sa==5'b00000)&(func==6'b00_1011);
    assign inst_movz    = op_d[6'b00_0000]&(sa==5'b00000)&(func==6'b00_1010);
    assign inst_mfhi    = op_d[6'b00_0000]&(inst[25:16]==10'b00000_00000)&(sa==5'b00000)&(func==6'b01_0000);
    assign inst_mflo    = op_d[6'b00_0000]&(inst[25:16]==10'b00000_00000)&(sa==5'b00000)&(func==6'b01_0010);
    assign inst_mthi    = op_d[6'b00_0000]&(inst[20:6]==15'b00000_00000_00000)&(func==6'b01_0001);
    assign inst_mtlo    = op_d[6'b00_0000]&(inst[20:6]==15'b00000_00000_00000)&(func==6'b01_0011);
    assign inst_div     = op_d[6'b00_0000]&(inst[15:6]==10'b00000_00000)&(func==6'b01_1010);
    assign inst_divu    = op_d[6'b00_0000]&(inst[15:6]==10'b00000_00000)&(func==6'b01_1011);
    assign inst_mult    = op_d[6'b00_0000]&(inst[15:6]==10'b00000_00000)&(func==6'b01_1000);
    assign inst_multu   = op_d[6'b00_0000]&(inst[15:6]==10'b00000_00000)&(func==6'b01_1001);
    assign inst_lb      = op_d[6'b10_0000];
    assign inst_lbu     = op_d[6'b10_0100];
    assign inst_lh      = op_d[6'b10_0001];
    assign inst_lhu     = op_d[6'b10_0101];
    assign inst_sb      = op_d[6'b10_1000];
    assign inst_sh      = op_d[6'b10_1001];

    wire [31:0] rdata1_lsa;
    assign inst_lsa = op_d[6'b01_1100]&(inst[10:8] == 3'b111)&(inst[5:0]==6'b110111);
    assign is_lsa = inst_lsa;
    assign rdata1_lsa = inst_lsa ? (rdata1 << ({1'b0,inst[7:6]} + 3'b001)):rdata1;
    

    // rs to reg1 指令不一定显示是rs，可能是base寄存器，但对应rs寄存器
    assign sel_alu_src1[0] = inst_ori | inst_addiu | inst_subu | inst_addu | inst_or | inst_lw | inst_sw | inst_xor
        | inst_and | inst_sltu | inst_slt | inst_slti | inst_sltiu | inst_srlv | inst_beq | inst_bne | inst_bgtz|inst_bltz
        | inst_add | inst_jr | inst_addi | inst_sub|inst_andi| inst_nor|inst_xori|inst_sllv| inst_srav|inst_bgez |inst_blez
        | inst_div | inst_divu | inst_mult | inst_multu
        | inst_mthi| inst_mtlo | inst_sh   | inst_sb   | inst_lhu 
        | inst_lh | inst_lb | inst_lbu | inst_lsa;

    // pc to reg1
    assign sel_alu_src1[1] =inst_jal| inst_j|inst_bltzal|inst_bgezal|inst_jalr;

    // sa_zero_extend to reg1
    assign sel_alu_src1[2] = inst_sll | inst_srl|inst_sra;

    
    // rt to reg2 不是看到rt就加在这里，有时rt是要存的，而不是读取的，不能加在这里
    assign sel_alu_src2[0] = inst_subu |inst_addu | inst_sll | inst_or | inst_xor | inst_and | inst_sltu
        | inst_slt | inst_srlv | inst_srl | inst_beq | inst_bne | inst_add | inst_sub|inst_nor|inst_sllv |inst_sra| inst_srav
        | inst_div | inst_divu| inst_mult| inst_multu 
        |inst_sh | inst_sb | inst_lhu | inst_lh | inst_lbu | inst_lsa;   
    
    // imm_sign_extend to reg2
    assign sel_alu_src2[1] = inst_lui | inst_addiu | inst_lw | inst_sw | inst_slti | inst_sltiu | inst_addi 
                            | inst_sh | inst_sb | inst_lhu | inst_lh | inst_lbu | inst_lb; 

    // 32'b8 to reg2
    assign sel_alu_src2[2] = inst_jal|inst_j|inst_bltzal|inst_bgezal|inst_jalr  ;

    // imm_zero_extend to reg2
    assign sel_alu_src2[3] = inst_ori|inst_andi|inst_xori;



    assign op_add = inst_addiu | inst_addu | inst_lw | inst_sw | inst_add |inst_jal|inst_addi|inst_bltzal|inst_bgezal|inst_jalr 
                    | inst_sh | inst_sb | inst_lhu | inst_lh | inst_lbu |  inst_lb | inst_lsa;
    assign op_sub = inst_subu | inst_sub;
    assign op_slt = inst_slt | inst_slti;
    assign op_sltu = inst_sltu | inst_sltiu;
    assign op_and = inst_and|inst_andi;
    assign op_nor = inst_nor;
    assign op_or = inst_ori | inst_or;
    assign op_xor = inst_xor|inst_xori;
    assign op_sll = inst_sll|inst_sllv ;
    assign op_srl = inst_srlv | inst_srl;
    assign op_sra = inst_sra| inst_srav;
    assign op_lui = inst_lui;
    

    assign alu_op = {op_add, op_sub, op_slt, op_sltu,
                     op_and, op_nor, op_or, op_xor,
                     op_sll, op_srl, op_sra, op_lui};


    //和访存有关
    // load and store enable
    assign data_ram_en = inst_lw | inst_sw | inst_sh | inst_sb | inst_lhu | inst_lh | inst_lbu |inst_lb;

    // write enable 写存储器则传入1111，不是则是0000，调换顺序会报错
    assign data_ram_wen = inst_sw ? 4'b1111:4'b0000;

    assign data_ram_readen =  inst_lw  ? 4'b1111 
                             :inst_lb  ? 4'b0001 
                             :inst_lbu ? 4'b0010
                             :inst_lh  ? 4'b0011
                             :inst_lhu ? 4'b0100
                             :inst_sb  ? 4'b0101
                             :inst_sh  ? 4'b0111
                             :4'b0000;
                             
    
    assign hi_read = inst_mfhi;                     
    assign lo_read = inst_mflo;                         
    assign hi_write = inst_mthi;                         
    assign lo_write = inst_mtlo; 
    //判断是否加气泡
    //要读取的reg1是否与上一条指令存在load相关
    wire stallreq_for_reg1_dataRelate;
    //要读取的reg2是否与上一条指令存在load相关
    wire stallreq_for_reg2_dataRelate;

    // //判断是否加气泡
    // //要读取的reg1是否与上一条指令存在load相关
    // reg stallreq_for_reg1_dataRelate;
    // //要读取的reg2是否与上一条指令存在load相关
    // reg stallreq_for_reg2_dataRelate;

    //上一条指令是否为load
    wire pre_inst_is_load;
    assign pre_inst_is_load = pre_inst_data_sram_en & (pre_inst_data_sram_wen == 4'b0000);



    assign stallreq_for_reg1_loadRelate = (rs == pre_ex_to_id_waddr) & sel_alu_src1[0];
    assign stallreq_for_reg2_loadRelate = (rt == pre_ex_to_id_waddr) & sel_alu_src2[0];
    assign stallreq_for_id = (stallreq_for_reg1_loadRelate | stallreq_for_reg2_loadRelate) & pre_inst_is_load;
    // always @ (posedge clk) begin
    //     if((rs == pre_ex_to_id_waddr) & sel_alu_src1[0] == 1'b1)
    //         stallreq_for_reg1_loadRelate <= `Stop;
    //     else
    //         stallreq_for_reg1_loadRelate <= `NoStop;
    //     if((rt == pre_ex_to_id_waddr) & sel_alu_src2[0] == 1'b1)
    //         stallreq_for_reg2_loadRelate <= `Stop;
    //     else
    //         stallreq_for_reg2_loadRelate <= `NoStop;
	// end



    // regfile store enable
    assign rf_we = inst_ori | inst_lui | inst_addiu | inst_subu | inst_jal |inst_addu | inst_sll | inst_or | inst_lw
        | inst_xor | inst_and | inst_sltu | inst_slt | inst_slti | inst_sltiu | inst_srlv | inst_srl | inst_add
        | inst_addi | inst_sub|inst_andi|inst_nor|inst_xori|inst_sllv|inst_sra|inst_srav|inst_bltzal |inst_bgezal|inst_jalr
        | inst_mflo| inst_mfhi
        | inst_lb | inst_lhu | inst_lh | inst_lbu | inst_lsa;


    // store in [rd]
    assign sel_rf_dst[0] = inst_subu | inst_addu | inst_sll | inst_or | inst_xor | inst_and | inst_sltu
        | inst_slt | inst_srlv | inst_srl | inst_add | inst_sub|inst_nor|inst_sllv|inst_sra | inst_srav|inst_jalr
        | inst_mflo| inst_mfhi | inst_lsa;
    // store in [rt] 
    assign sel_rf_dst[1] = inst_ori | inst_lui | inst_addiu | inst_lw | inst_slti | inst_sltiu | inst_addi|inst_andi|inst_xori 
                          |inst_lhu | inst_lh | inst_lbu | inst_lb;
    // store in [31]
    assign sel_rf_dst[2] = inst_jal|inst_bltzal|inst_bgezal;

    // sel for regfile address
    assign rf_waddr = {5{sel_rf_dst[0]}} & rd 
                    | {5{sel_rf_dst[1]}} & rt
                    | {5{sel_rf_dst[2]}} & 32'd31;

    // 0 from alu_res ; 1 from ld_res
    assign sel_rf_res = 1'b0; 
//    assign sel_rf_res = inst_lw; 

    assign id_to_ex_bus = {
        is_lsa,
        data_ram_readen,//230:227
        hi_read,        //226
        lo_read,        //225
        hi_write,       //224
        lo_write,       //223
        //红
        hi_out_file,    // 222:191
        lo_out_file,    // 190:159
        //红
        id_pc,          // 158:127
        inst,           // 126:95
        alu_op,         // 94:83
        sel_alu_src1,   // 82:80
        sel_alu_src2,   // 79:76
        data_ram_en,    // 75
        data_ram_wen,   // 74:71
        rf_we,          // 70
        rf_waddr,       // 69:65
        sel_rf_res,     // 64
        //rdata1,         // 63:32
        rdata1_lsa,     // 63:32
        rdata2          // 31:0
    };


    wire br_e;
    wire jr_e;
    wire [31:0] br_addr;
    wire rs_eq_rt;
    wire rs_ge_z;
    wire rs_gt_z;
    wire rs_le_z;
    wire rs_lt_z;
    wire [31:0] pc_plus_4;
    
    //beq
    assign pc_plus_4 = id_pc + 32'h4;

    assign rs_eq_rt = (rdata1 == rdata2);
    assign rs_gt_z = ( $signed(rdata1) > 0);
    assign rs_ge_z = (~rdata1[31]);
    assign rs_le_z = ~rs_gt_z;
    assign rs_lt_z = (rdata1[31]==1'b1);

    assign br_e = (inst_beq & rs_eq_rt) | inst_jr | inst_jal|inst_jalr  | (inst_bne & ~rs_eq_rt) | inst_j | (inst_bgtz & rs_gt_z)
    |(inst_bgez & rs_ge_z)|(inst_blez & rs_le_z)|(inst_bltz & rs_lt_z) |(inst_bltzal & rs_lt_z)|(inst_bgezal & rs_ge_z) ;
    assign br_addr = (inst_beq | inst_bne | inst_bgtz|inst_bgez|inst_blez|inst_bltz|inst_bltzal|inst_bgezal) ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}):
                    (inst_jr|inst_jalr  ) ? rdata1 :
                    (inst_jal | inst_j) ? ({id_pc[31:28],inst[25:0],2'b0}) :32'b0;
    
    
    
    
    
    

    assign br_bus = {
        br_e,
        br_addr
    };
    


endmodule

