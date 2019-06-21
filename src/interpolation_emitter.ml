type element = string*Location.t
type token = String of element
           | Expression of element*element option
           | Variable of element*element option

let token_to_string = function String (s,_) -> s
                             | Expression ((e,_),_) -> "{" ^ e ^ "}"
                             | Variable ((v,_),_)   -> "[" ^ v ^ "]"

let print_tokens = List.iter (fun p -> print_string (token_to_string p))

(* Convert commented out expression to a string.
   Here we also rely on UTF8/single codepage - '(','*' and ')' occupy only one byte. *)
let convert_commented_out = function
  | Expression ((str, loc), fmt) ->
        if String.length str >= 4 && String.get str 1 = '*' &&
                       String.get str (String.length str - 2) = '*' then
            match fmt with
            | Some (fmt, _) -> String (fmt ^ "$" ^ str, loc)
            | None -> String ("$" ^ str, loc)
        else
            Expression ((str, loc), fmt)
  | x -> x

(* Generate a list of sprintf arguments from tokens. *)
let to_arguments tokens = List.rev @@ List.fold_left
    (fun acc token -> match token with
        | Expression ((e, _), _) -> (Asttypes.Nolabel, Parse.expression (Lexing.from_string e))::acc
        | Variable ((v, _), _) -> (Asttypes.Nolabel, Parse.expression (Lexing.from_string v))::acc
        | _ -> acc
    ) [] tokens

(* Generate format string for sprintf from tokens. *)
let to_format_string tokens =
    let joined = String.concat "" @@ List.rev @@ List.fold_left
                (fun acc token -> match token with
                    | Expression (_, Some (fmt, _)) -> fmt::acc
                    | Expression (_, None) -> "%s"::acc
                    | Variable (_, Some (fmt, _)) -> fmt::acc
                    | Variable (_, None) -> "%s"::acc
                    | String (s, _) -> s::acc
                ) [] tokens in
    Parsetree.{
        pexp_desc = Pexp_constant (Pconst_string (joined, None));
        pexp_loc = Location.none;
        pexp_attributes = [] (*[Ast_mapper.attribute_of_warning Location.none
                            "Test warning"] *)
    }

(* Convert list of expressions with formats to ast.
   This function works for both format before value "%f$var" and
   value before format "$var%f" (scala style).
*)
let generate tokens =
    let sprintf = let open Longident in
        Parsetree.{
            pexp_desc = Pexp_ident {txt = Ldot (Lident "Printf", "sprintf"); loc = Location.none};
            pexp_loc = Location.none;
            pexp_attributes = []
        } in
    let apply func args =
        Parsetree.{
            pexp_desc = Pexp_apply (func, args);
            pexp_loc = Location.none;
            pexp_attributes = []
        } in
    let format_string = to_format_string tokens in
    match to_arguments tokens with
    | [] -> format_string
    | args -> apply sprintf @@ (Asttypes.Nolabel,format_string)::args

let emit_ast tokens =
    List.map convert_commented_out tokens |> generate
