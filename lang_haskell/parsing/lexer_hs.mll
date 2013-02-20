{
(* Yoann Padioleau
 *
 * Copyright (C) 2010 Facebook
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)

open Common 

module Flag = Flag_parsing_hs

open Parser_hs

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(* src:
 * http://www.haskell.org/onlinereport/lexemes.html#sect2
 *)
(*****************************************************************************)
(* Wrappers *)
(*****************************************************************************)
let pr2, pr2_once = Common2.mk_pr2_wrappers Flag.verbose_lexing 

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)
exception Lexical of string

(* ---------------------------------------------------------------------- *)
let tok     lexbuf  = 
  Lexing.lexeme lexbuf
let tokinfo lexbuf  = 
  Parse_info.tokinfo_str_pos (Lexing.lexeme lexbuf) (Lexing.lexeme_start lexbuf)

(* ---------------------------------------------------------------------- *)
let keyword_table = Common.hash_of_list [
  "data", (fun ii -> Tdata ii);
  "newtype", (fun ii -> Tnewtype ii);
  "type", (fun ii -> Ttype ii);

  "class", (fun ii -> Tclass ii); 
  "instance", (fun ii -> Tinstance ii);

  "default", (fun ii -> Tdefault ii); 
  "deriving", (fun ii -> Tderiving ii); 

  "do", (fun ii -> Tdo ii); 

  "if", (fun ii -> Tif ii); 
  "then", (fun ii -> Tthen ii); 
  "else", (fun ii -> Telse ii); 

  "case", (fun ii -> Tcase ii); 
  "of", (fun ii -> Tof ii);

  "module", (fun ii -> Tmodule ii); 
  "import", (fun ii -> Timport ii); 

  "let", (fun ii -> Tlet ii); 
  "in", (fun ii -> Tin ii); 
  "where", (fun ii -> Twhere ii);

  "infix", (fun ii -> Tinfix ii); 
  "infixl", (fun ii -> Tinfixl ii); 
  "infixr", (fun ii -> Tinfixr ii);


  (* additional keywords not in spec *)
  "qualified", (fun ii -> Tqualified ii);
  "hiding", (fun ii -> Thiding ii);
  "as", (fun ii -> Tas ii);
]

}

(*****************************************************************************)
let letter = ['a'-'z''A'-'Z']
let digit = ['0'-'9']

let lowerletter = ['a'-'z']
let upperletter = ['A'-'Z']

let ident      = (lowerletter | '_') (letter | digit | '_' | "'")*
let upperident = upperletter (letter | digit | '_')*

let symbol =
  ['-' '+' '=' '~'  '.'  '/' ':' '<' '>' '*' '#' '_'  '?' '^' '!' '&'
    '|'
    '$'
   (* todo: should be its own token probably *)
   '\\' (* for lambdas *)
   '@'  (* as pattern *)
   (* '"' '`' *)
  ]

(*****************************************************************************)
rule token = parse

  (* ----------------------------------------------------------------------- *)
  (* spacing/comments *)
  (* ----------------------------------------------------------------------- *)
  | "--" [^'\n' '\r']* { 
      TComment(tokinfo lexbuf)
    }
  | "{-" { 
      let info = tokinfo lexbuf in 
      let com = comment lexbuf in
      TComment(info +> Parse_info.tok_add_s com)
    }

  | [' ''\t']+ { TCommentSpace (tokinfo lexbuf) }
  | "\n" { TCommentNewline (tokinfo lexbuf) }

  (* ----------------------------------------------------------------------- *)
  (* Symbols *)
  (* ----------------------------------------------------------------------- *)

  | '(' { TOParen (tokinfo lexbuf) }   | ')' { TCParen (tokinfo lexbuf) }
  | "[" { TOBracket(tokinfo lexbuf) }  | "]" { TCBracket(tokinfo lexbuf) }
  | "{" { TOBrace(tokinfo lexbuf) }    | "}" { TCBrace(tokinfo lexbuf) }
  | "," { TComma (tokinfo lexbuf) }
  | ";" { TSemiColon (tokinfo lexbuf) }
  | "|" { TPipe (tokinfo lexbuf) }

  | symbol+ { TSymbol (tok lexbuf, tokinfo lexbuf) }
  (* ----------------------------------------------------------------------- *)
  (* Strings *)
  (* ----------------------------------------------------------------------- *)
  | '"' {
      (* opti: use Buffer because some autogenerated files can
       * contains huge strings
       *)
      let info = tokinfo lexbuf in
      let buf = Buffer.create 100 in
      string buf lexbuf;
      let s = Buffer.contents buf in
      TString (s, info +> Parse_info.tok_add_s (s ^ "\""))
    }

  (* ----------------------------------------------------------------------- *)
  (* Chars *)
  (* ----------------------------------------------------------------------- *)

  | "'" (_ as c) "'" {
      TChar (String.make 1 c, tokinfo lexbuf)
    }

  (* ----------------------------------------------------------------------- *)
  (* Keywords and ident *)
  (* ----------------------------------------------------------------------- *)
  | ident {
      let info = tokinfo lexbuf in
      let s = tok lexbuf in
      match Common2.optionise (fun () -> Hashtbl.find keyword_table s) with
      | Some f -> f info
      | None -> TIdent (s, info)
    }

  | upperident {
      let s = tok lexbuf in
      TUpperIdent (s, tokinfo lexbuf)
    }

  | '`' ident '`' {
      (* todo: make it a TIdentInfix ? *)
      TSymbol (tok lexbuf, tokinfo lexbuf)
    }
  (* ----------------------------------------------------------------------- *)
  (* Constant *)
  (* ----------------------------------------------------------------------- *)

  | digit+ {
      TNumber(tok lexbuf, tokinfo lexbuf)
    }

  (* ----------------------------------------------------------------------- *)
  | eof { EOF (tokinfo lexbuf +> Parse_info.rewrap_str "") }
  | _ { 
        if !Flag.verbose_lexing 
        then pr2_once ("LEXER:unrecognised symbol, in token rule:"^tok lexbuf);
        TUnknown (tokinfo lexbuf)
    }

(*****************************************************************************)

and string buf = parse
  | '"'           { Buffer.add_string buf "" }
  (* opti: *)
  | [^ '"' '\\']+ { 
      Buffer.add_string buf (tok lexbuf);
      string buf lexbuf 
    }

  | ("\\" (_ as v)) as x { 
      (* todo: check char ? *)
      (match v with
      | _ -> ()
      );
      Buffer.add_string buf x;
      string buf lexbuf
    }
  | eof { 
      pr2 "LEXER: WIERD end of file in double quoted string";
    }

(*****************************************************************************)
and comment = parse
  | "-}" { tok lexbuf }

  | "{-" { 
      (* in haskell comments are nestable *)
      let s = comment lexbuf in
      s ^ comment lexbuf
    }

  (* noteopti: bugfix, need add '(' too *)

  | [^'-''{']+ { let s = tok lexbuf in s ^ comment lexbuf } 
  | "-"     { let s = tok lexbuf in s ^ comment lexbuf }
  | "{"     { let s = tok lexbuf in s ^ comment lexbuf }
  | eof { pr2 "LEXER: end of file in comment"; "-}"}
  | _  { 
      let s = tok lexbuf in
      pr2 ("LEXER: unrecognised symbol in comment:"^s);
      s ^ comment lexbuf
    }
