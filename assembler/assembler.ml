open Str
 
type instrtype = Ntype | Set | Ptype | Wait | Count | Btype
 
let instr_arr = [
    ("HALT", 0x00); (* HALT *)
    ("SET", 0x01); (* SET pin, value*)
    ("WAIT", 0x02); (* WAIT cycles *)
    ("LOAD_TX", 0x03); (* LOAD_TX *)
    ("OUT_BIT", 0x04); (* OUT_BIT pin *)
    ("SHIFT_TX", 0x05); (* SHIFT TX *)
    ("CLEAR_RX", 0x06); (* CLEAR_RX *)
    ("SAMPLE", 0x07); (* SAMPLE pin *)
    ("COUNT", 0x08); (* COUNT n *)
    ("LOOP", 0x09); (* LOOP address *)
    ("JUMP", 0xA); (* JUMP address *)
]
(*
Methodology: UIOX bidirectional pins, UIX input only, UO output only

8 bidrectional, 8 Input only, 8 output only

*)
let pins = [
    ("UIO0", 0);
    ("UIO1", 1);
    ("UIO2", 2);
    ("UIO3", 3);
    ("UIO4", 4);
    ("UIO5", 5);
    ("UIO6", 6);
    ("UIO7", 7);
    ("UI0", 8);
    ("UI1", 9);
    ("UI2", 10);
    ("UI3", 11);
    ("UI4", 12);
    ("UI5", 13);
    ("UI6", 14);
    ("UI7", 15);
    ("UO0", 16);
    ("UO1", 17);
    ("UO2", 18);
    ("UO3", 19);
    ("UO4", 20);
    ("UO5", 21);
    ("UO6", 22);
    ("UO7", 23)
]
 
let check instr =
    match List.assoc_opt instr instr_arr with
    | Some opcode -> (match opcode with
        | 0x00 | 0x03 | 0x05 | 0x06 -> Ntype
        | 0x01 -> Set
        | 0x02 -> Wait
        | 0x04 | 0x07 -> Ptype
        | 0x08 -> Count
        | 0x09 | 0x0A -> Btype
        | _ -> failwith ("unknown opcode: " ^ instr))
    | None -> failwith ("unknown instruction: " ^ instr)
 
let argcount ty = match ty with
    | Ntype -> 0
    | Set -> 2
    | Ptype | Wait | Count | Btype -> 1
 
let encodeP instr pin bit =
    let opcode = List.assoc instr instr_arr in
    (opcode lsl 12) lor (pin lsl 7) lor (bit lsl 6)
 
let encodeImm instr imm =
    let opcode = List.assoc instr instr_arr in
    (opcode lsl 12) lor imm
 
let pinvert pin = match List.assoc_opt pin pins with
    | Some a -> a
    | None -> failwith ("unknown pin: " ^ pin)
 
let outpin pin =
    let a = pinvert pin in
    if a >= 8 && a < 16 then failwith ("can't drive input-only pin: " ^ pin) else a
 
let inpin pin =
    let a = pinvert pin in
    if a >= 16 then failwith ("can't sample output-only pin: " ^ pin) else a
 
let numvert num = match int_of_string_opt num with
    | Some a -> a
    | None -> failwith ("bad number: " ^ num)
 
let rangecheck name lo hi v =
    if v < lo || v > hi then failwith (name ^ " out of range: " ^ string_of_int v) else v
 
let infile = if Array.length Sys.argv > 1 then Sys.argv.(1) else "test1.txt"
 
let outfile = if Array.length Sys.argv > 2 then Sys.argv.(2) else "results.hex"
 
let depth = if Array.length Sys.argv > 3 then rangecheck "depth" 1 64 (numvert Sys.argv.(3)) else 64
 
let contents = In_channel.with_open_text infile In_channel.input_all
 
let filesplitter input = String.split_on_char '\n' input
 
let commstrip input = List.map (fun x -> match Str.split_delim (Str.regexp "[#;]\\|//") x with
    | [] -> ""
    | h :: _ -> h
    ) input
 
let linesplitter input = List.map (fun x -> Str.split (Str.regexp "[ \t,\r]+") x) input
 
let stripempty input = List.filter (fun x -> x <> []) input
 
let increment = ref 0
 
let acc () = increment := !increment + 1
 
let symbols = Hashtbl.create 10
 
let insertsymbol input =
    if Hashtbl.mem symbols input then failwith ("duplicate label: " ^ input)
    else Hashtbl.replace symbols input !increment
 
let run1 input = List.iter (fun x ->
    match x with
    | [] -> ()
    | h :: t ->
        if String.contains h ':' then begin
            insertsymbol (List.hd (String.split_on_char ':' h));
            if t <> [] then acc ()
        end else acc ()
    ) input
 
let transfer input =
    match Hashtbl.find_opt symbols input with
    | Some target -> target
    | None -> (match int_of_string_opt input with
        | Some a -> a
        | None -> failwith ("unknown label: " ^ input))
 
let stripsymbol x = match x with
    | h :: t when String.contains h ':' -> t
    | _ -> x
 
let run2 input = List.filter_map (fun x ->
    match stripsymbol x with
    | [] -> None
    | h :: t ->
        let ty = check h in
        if List.length t <> argcount ty then failwith ("wrong number of operands: " ^ h);
        let word = (match ty with
        | Ntype -> encodeImm h 0
        | Set ->
            let pin = outpin (List.nth t 0) in
            let value = rangecheck h 0 1 (numvert (List.nth t 1)) in
            encodeP h pin value
        | Ptype ->
            let pin = if h = "SAMPLE" then inpin (List.nth t 0) else outpin (List.nth t 0) in
            encodeP h pin 0
        | Wait ->
            let cycles = rangecheck h 1 4095 (numvert (List.nth t 0)) in
            encodeImm h cycles
        | Count ->
            let n = rangecheck h 1 255 (numvert (List.nth t 0)) in
            encodeImm h n
        | Btype ->
            let address = rangecheck h 0 (depth - 1) (transfer (List.nth t 0)) in
            encodeImm h address)
        in
        Some word
    ) input
 
let outhex filename words =
    let oc = open_out filename in
    List.iter (fun word -> Printf.fprintf oc "%04X\n" word) words;
    for _ = List.length words to depth - 1 do output_string oc "0000\n" done;
    close_out oc
 
let parsed = contents |> filesplitter |> commstrip |> linesplitter |> stripempty
 
let () = run1 parsed
 
let () = if !increment > depth then failwith ("program too long: " ^ string_of_int !increment ^ " words")
 
let encoded = run2 parsed
 
let () = outhex outfile encoded
 
