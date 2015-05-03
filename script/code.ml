(* Syntax hightlight code and eval ocaml toplevel phrases *)

open Core_kernel.Std
open Async.Std
open Printf
open Scanf
open Utils

(* To HTML, with syntax highlighting
 ***********************************************************************)

let html_encode =
  let enc = Netencoding.Html.encode ~in_enc:`Enc_utf8 () in
  fun s ->
  try enc s
  with Netconversion.Malformed_code ->
    failwith(sprintf "Code.html_encode: \"%s\" cannot be encoded to HTML" s)

let html_decode =
  Netencoding.Html.decode ~in_enc:`Enc_utf8 ~out_enc:`Enc_utf8 ()


let highlight_ocaml =
  (* Simple minded engine to highlight OCaml code.  The [phrase] is supposed
     NOT to be html encoded. *)
  let id = "\\b[a-z_][a-zA-Z0-9_']*" in
  let let_id = id ^ "\\|( +[!=+-*/^:]+ +)" in
  let uid = "\\b[A-Z][A-Za-z0-9_']*" in
  (* Arguments to functions may pattern match.  Final "\\." to allow
     "..." in argument (sometimes used for explanations). *)
  let args = "\\(\\?(" ^ id ^ " *=[^=()]+) +\\|[~?]" ^ id ^ "[ :]+\\|() *\\|"
             ^ id ^ " +\\|(" ^ id ^ "\\( *:[^)]+\\)?) +\\|([a-zA-Z0-9_', ]+) *"
             ^ "\\|{[a-zA-Z0-9_',; ]+} *\\|\\.+ +\\)+" in
  let subst = [ (* regex, replacement *)
    (let cmt_txt = "\\([^()]\\|([^*])\\|([^*][^()]*[^*])\\)*" in
     "\\((\\*\\((\\*" ^ cmt_txt ^ "\\*)\\|" ^ cmt_txt ^ "\\)+\\*)\\)",
     "<span class=\"comment\">\\1</span>");
    (";; *\n", "<span class=\"ocaml-prompt\">;;</span><br/>");
    ("\\blet +() *=", "<span class=\"governing\">let</span> () =");
    ("\\band +\\('[_a-z]+ +\\(" ^ let_id ^ "\\)\\) *= *",
     "<span class=\"governing\">and</span> \
      <span class=\"type\">\\1</span> = ");
    ("\\b\\(let +rec\\|let\\|and\\) +\\(" ^ let_id ^ "\\) *= *function",
     "<span class=\"governing\">\\1</span> <span class=\"ocaml-function\">\
      \\2</span> = <span class=\"keyword\">function</span>");
    ("\\b\\(let +rec\\|let\\|and\\) +\\(" ^ let_id ^ "\\) +\\("
     ^ args ^ "\\)= *function",
     "<span class=\"governing\">\\1</span> <span class=\"ocaml-function\">\
      \\2</span> <span class=\"ocaml-variable\">\\3</span>= \
      <span class=\"keyword\">function</span>");
    ("\\b\\(let +rec\\|let\\|and\\) +\\(" ^ let_id ^ "\\) +: *\\([^=]+\\)"
     ^ "= *function",
     "<span class=\"governing\">\\1</span> <span class=\"ocaml-function\">\
      \\2</span> : <span class=\"type\">\\3</span>= \
      <span class=\"keyword\">function</span>");
    ("\\b\\(let +rec\\|let\\|and\\) +\\(" ^ let_id ^ "\\) +\\(" ^ args ^ "\\)=",
     "<span class=\"governing\">\\1</span> <span class=\"ocaml-function\">\
      \\2</span> <span class=\"ocaml-variable\">\\3</span>=");
    ("\\b\\(let +\\(rec +\\)?\\|and +\\)\\(" ^ let_id ^ "\\) *=",
     "<span class=\"governing\">\\1</span>\
      <span class=\"ocaml-variable\">\\3</span> =");
    ("\\b\\(let +\\(rec\\)?\\|and\\)\\b",
     "<span class=\"governing\">\\1</span>");
    ("\\bexternal +\\(" ^ let_id ^ "\\) +:",
     "<span class=\"governing\">external</span> \
      <span class=\"ocaml-function\">\\1</span>&nbsp;:");
    ("\\btype +\\(\\('[a-z_]+ +\\)*\\)\\(" ^ id ^ "\\)\\( *=\\| *$\\)",
     "type <span class=\"type\">\\1\\3</span>\\4");
    ("open +\\(\\(" ^ uid ^ "\\.\\)*\\)\\(" ^ uid ^ "\\)",
     "<span class=\"governing\">open</span> \\1\
      <span class=\"ocaml-module\">\\3</span>");
    ("\\(" ^ uid ^ "\\)\\.",
     "<span class=\"ocaml-module\">\\1</span>.");
    ("module +\\(" ^ uid ^ "\\) *= *\
                            \\(\\(" ^ uid ^ "\\.\\)*\\)\\(" ^ uid ^ "\\)",
     "<span class=\"governing\">module</span> \
      <span class=\"ocaml-module\">\\1</span> \
      = \\2<span class=\"ocaml-module\">\\4</span>");
    ("\\(module\\|module type\\) +\\(" ^ uid ^ "\\) *"
     ^ "\\(\\(([^)]+)\\)* *\\)=",
     "<span class=\"governing\">\\1</span> \
      <span class=\"ocaml-module\">\\2</span> \
      <span class=\"ocaml-variable\">\\3</span>=");
    ("module +\\(" ^ uid ^ "\\) *\\(\\(([^)]+)\\)* *\\): *\\(" ^ uid ^ "\\) *=",
     "<span class=\"governing\">module</span> \
      <span class=\"ocaml-module\">\\1</span> \
      <span class=\"ocaml-variable\">\\2</span>\
      : <span class=\"ocaml-module\">\\4</span> =");
    ("module +\\(" ^ uid ^ "\\) *\\(\\(([^)]+)\\)* *\\):",
     "<span class=\"governing\">module</span> \
      <span class=\"ocaml-module\">\\1</span> \
      <span class=\"ocaml-variable\">\\2</span>:");
    ("\\b\\(class\\( +virtual\\|\\)?\\) +\\(" ^ id ^
       "\\) +\\(\\(" ^ args ^ "\\)?\\)=",
     "<span class=\"governing\">\\1</span> \
      <span class=\"ocaml-function\">\\3</span> \
      <span class=\"ocaml-variable\">\\4</span>=");
    ("\\bval +\\(" ^ id ^ "\\) *=",
     "<span class=\"governing\">val</span> \
      <span class=\"ocaml-variable\">\\1</span> =");
    ("\\bval +\\(" ^ id ^ "\\) *:",
     "<span class=\"governing\">val</span> \
      <span class=\"ocaml-function\">\\1</span> :");
    ("\\bmethod +\\(" ^ id ^ "\\)\\(\\( *: *[^ =]+\\)?\\) *=",
     "<span class=\"governing\">method</span> <span class=\"ocaml-function\">\
      \\1</span><span class=\"type\">\\2</span> =");
    ("\\bmethod +\\(" ^ id ^ "\\) +\\(" ^ args ^ "\\) *=",
     "<span class=\"governing\">method</span> <span class=\"ocaml-function\">\
      \\1</span> <span class=\"ocaml-variable\">\\2</span>=");
    ("\\b\\(type\\|in\\|begin\\|end\\|struct\\|sig\\|val\\|\
      object\\|inherit\\|initializer\\|include\\)\\b\\([^\"]\\)",
     "<span class=\"governing\">\\1</span>\\2");
    ("\\b\\(end\\)$", "<span class=\"governing\">\\1</span>");
    ("\\b\\(fun\\|as\\|of\\|if\\|then\\|else\\|match\\|with\
      \\|for\\|to\\|do\\|downto\\|done\\|while\
      \\|raise\\|failwith\\|try\\|assert\
      \\|ref\\|mutable\\|new\\)\\b",
     "<span class=\"keyword\">\\1</span>");
  ] in
  let subst = List.map subst ~f:(fun (re, t) -> (Str.regexp re, t)) in
  let beg_quot = Str.regexp "&quot;" in
  let end_quot = Str.regexp "[^\\]&quot;" in
  let rec color_string s =
    try
      let i1 = Str.search_forward beg_quot s 0 in
      try
        let i2 = Str.search_forward end_quot s (i1 + 5) + 7 in
        let before = String.sub s 0 i1 in
        let qstring = String.sub s i1 (i2 - i1) in
        let tail = color_string (String.sub s i2 (String.length s - i2)) in
        before ^ "<span class=\"string\">" ^ qstring ^ "</span>" ^ tail
      with Not_found -> s (* quoted string not well terminated, bail out *)
    with Not_found -> s (* no quote *)
  in
  fun phrase -> (
    let phrase = color_string(html_encode phrase) in
    let p = List.fold_left ~f:(fun h (re, t) -> Str.global_replace re t h)
                           ~init:phrase subst in
    (* Wrap the code in a <pre> block so no Omd.Paragraph are generated, etc. *)
    match Omd.of_string ("<pre>" ^ p ^ "</pre>") with
    | [Omd.Html_block(_,_,o)] -> o
    | _ -> assert false
  )

let highlight ?(syntax="ocaml") phrase =
  if syntax = "ocaml" then highlight_ocaml phrase
  else [Omd.Raw(html_encode phrase)]


(* Eval OCaml code — in the same way the toploop does
 ***********************************************************************)

(** Return the same document as [md] but with all strings transformed
    by [f].  [f] is applied in the order of appearance of the strings. *)
let rec omd_map_string f md =
  List.map md ~f:(omd_map_string_el f)
and omd_map_string_el f md =
  let open Omd in
  match md with
  | H1 o -> H1(omd_map_string f o)
  | H2 o -> H2(omd_map_string f o)
  | H3 o -> H3(omd_map_string f o)
  | H4 o -> H4(omd_map_string f o)
  | H5 o -> H5(omd_map_string f o)
  | H6 o -> H6(omd_map_string f o)
  | Paragraph o -> Paragraph(omd_map_string f o)
  | Text s -> Text(f s)
  | Emph o -> Emph(omd_map_string f o)
  | Bold o -> Bold(omd_map_string f o)
  | Ul o -> Ul(List.map ~f:(omd_map_string f) o)
  | Ol o -> Ol(List.map ~f:(omd_map_string f) o)
  | Ulp o -> Ulp(List.map ~f:(omd_map_string f) o)
  | Olp o -> Olp(List.map ~f:(omd_map_string f) o)
  | Code(name, s) -> Code(name, f s)
  | Code_block(name, s) -> Code_block(name, f s)
  | Url(h, o, t) -> Url(h, omd_map_string f o, t)
  | Html(name, args, o) -> Html(name, args, omd_map_string f o)
  | Html_block(name, args, o) -> Html_block(name, args, omd_map_string f o)
  | Raw s -> Raw(f s)
  | Raw_block s -> Raw_block(f s)
  | Blockquote o -> Blockquote(omd_map_string f o)
  | e -> e

let add_prompt =
  let nl_re = Str.regexp "[\n\r]" in
  let indent_string s = Str.global_replace nl_re "\n  " s in
  fun phrase ->
  (* Due to the prompt, one must add 2 spaces at the beginnig of each line *)
  let phrase = omd_map_string indent_string phrase in
  let open Omd in
  [Html("span", ["class", Some "ocaml-prompt"], [Raw "# "]);
   Html("span", ["class", Some "ocaml-input"],  phrase);
   Html("span", ["class", Some "ocaml-prompt"], [Raw ";;"])]

let format_eval_input phrase : Omd.t =
  add_prompt (highlight_ocaml phrase)

let html_of_eval_silent t phrase =
  Oloop.eval t phrase
  >>| (function
        | `Eval _ -> ()
        | `Uneval(_, s) ->
           (* As no output shows in the rendered page, we deem it
              useful to have errors reported at least in the
              compilation buffer. *)
           eprintf "Error %S during silent evaluation of the phrase %S\n"
                   s phrase
      ) >>| fun () ->
  format_eval_input phrase


let rec omd_transform_text f md =
  List.rev (List.fold_left ~f:(omd_transform_text_el f) ~init:[] md)
and omd_transform_text_el f acc md =
  let open Omd in
  match md with
  | H1 o -> H1(omd_transform_text f o) :: acc
  | H2 o -> H2(omd_transform_text f o) :: acc
  | H3 o -> H3(omd_transform_text f o) :: acc
  | H4 o -> H4(omd_transform_text f o) :: acc
  | H5 o -> H5(omd_transform_text f o) :: acc
  | H6 o -> H6(omd_transform_text f o) :: acc
  | Paragraph o -> Paragraph(omd_transform_text f o) :: acc
  | Text s | Raw s -> List.rev_append (f s) acc
  | Emph o -> Emph(omd_transform_text f o) :: acc
  | Bold o -> Bold(omd_transform_text f o) :: acc
  | Ul o -> Ul(List.map ~f:(omd_transform_text f) o) :: acc
  | Ol o -> Ol(List.map ~f:(omd_transform_text f) o) :: acc
  | Ulp o -> Ulp(List.map ~f:(omd_transform_text f) o) :: acc
  | Olp o -> Olp(List.map ~f:(omd_transform_text f) o) :: acc
  | Url(h, o, t) -> Url(h, omd_transform_text f o, t) :: acc
  | Html(name, args, o) -> Html(name, args, omd_transform_text f o) :: acc
  | Html_block(name, args, o) ->
     Html_block(name, args, omd_transform_text f o) :: acc
  | Blockquote o -> Blockquote(omd_transform_text f o) :: acc
  | e -> e :: acc

let html_error txt =
  Omd.Html_block("span", ["class", Some "ocaml-error-loc"],
                 [Omd.Raw(html_encode txt)])

(* Insert the HTML code to highligh the error located in [phrase] at
   chars [c1 .. c2[.  [phrase] is a syntax highlighted HTML
   representation of the code. *)
let highlight_error_range phrase c1 c2 =
  let c1 = ref c1 and c2 = ref c2 in
  let split html =
    let txt = html_decode html in
    let len = String.length txt in
    let r =
      if len <= !c1 || !c2 < 0 then [Omd.Raw html]
      else if !c1 > 0 then
        let p1 = String.sub txt 0 !c1 in
        if !c2 < len then
          let p2 = String.sub txt !c1 (!c2 - !c1)
          and p3 = String.sub txt !c2 (len - !c2) in
          [Omd.Raw(html_encode p1);  html_error p2;  Omd.Raw(html_encode p3)]
        else (* c2 >= len *)
          let p2 = String.sub txt !c1 (len - !c1) in
          [Omd.Raw(html_encode p1);  html_error p2]
      else (* c1 <= 0 *)
        if !c2 < len then
          let p2 = String.sub txt 0 !c2
          and p3 = String.sub txt !c2 (len - !c2) in
          [html_error p2;  Omd.Raw(html_encode p3)]
        else (* c2 >= len *)
          [html_error txt] in
    c1 := !c1 - len;  c2 := !c2 - len;
    r in
  let phrase = omd_transform_text split phrase in
  (phrase: Omd.t)


(* Process [err_msg] to see whether one needs to highlight part of the
   [phrase].  *)
let highlight_error phrase loc =
  let c1 = loc.Location.loc_start.Lexing.pos_cnum in
  let c2 = loc.Location.loc_end.Lexing.pos_cnum in
  let phrase = highlight_ocaml phrase in
  highlight_error_range phrase c1 c2

let html_of_eval t phrase =
  Oloop.eval t phrase
  >>| (function
        | `Eval o ->
           let b = Buffer.create 1024 in
           !Oprint.out_phrase (Format.formatter_of_buffer b)
            (Oloop.Outcome.result o);
           highlight_ocaml phrase, "ocaml-output",
           [Omd.Html("span", ["class", Some "ocaml-stdout"],
                     [Omd.Raw(html_encode(Oloop.Outcome.stdout o))]);
            Omd.Html("span", ["class", Some "ocaml-stderr"],
                     [Omd.Raw(html_encode(Oloop.Outcome.stderr o))]);
           Omd.Raw(html_encode(Buffer.contents b))]
        | `Uneval(e, msg) ->
           let phrase = match Oloop.Outcome.location_of_uneval e with
             | Some loc -> highlight_error phrase loc
             | None -> highlight_ocaml phrase in
           phrase, "ocaml-error", [Omd.Raw(html_encode(msg))]
      ) >>| fun (phrase, cls, out) ->
  add_prompt phrase
  @ [ Omd.Html("br", [], []);
      Omd.Html("span", ["class", Some cls], out) ]


(* FIXME: naive, ";;" can occur inside strings and one does not want
   to split it then.  Could be more efficient *)
let end_of_phrase = Str.regexp ";;[ \t\n]*"


let to_html t phrases : Omd.t Deferred.t =
  (* Split phrases *)
  let phrases = List.map ~f:String.strip (Str.split end_of_phrase phrases) in
  Deferred.List.map ~f:(html_of_eval t) phrases >>| fun l ->
  List.concat l


(* Local Variables: *)
(* compile-command: "make --no-print-directory -k -C .. script/md_preprocess" *)
(* End: *)
