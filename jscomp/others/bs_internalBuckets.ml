(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file ../LICENSE.     *)
(*                                                                     *)
(***********************************************************************)
(**  Adapted by Authors of BuckleScript 2017                           *)

(* For JS backends, we use [undefined] as default value, so that buckets
   could be allocated lazily
*)

(* We do dynamic hashing, and resize the table and rehash the elements
   when buckets become too long. *)
(* and ('a,'b) buckets 
=    
 < key : 'a [@bs.set]; 
   value : 'b [@bs.set];
   next : ('a,'b) buckets opt [@bs.set]
  > Js.t *)
    (* {
      mutable key : 'a ; 
      mutable value : 'b ; 
      mutable next : ('a, 'b) buckets opt
    } *)

#if BS then
type 'a opt = 'a Js.undefined
#else 
type 'a opt = 'a option 
#end

type ('a,'b) bucket = {
  mutable key : 'a;
  mutable value : 'b;
  mutable next : ('a,'b) bucket opt
}  

and ('a,'b) bucket_opt = ('a, 'b) bucket opt


and ('a, 'b,'id) t0 =
  { mutable size: int;                        (* number of entries *)
    mutable buckets: ('a, 'b) bucket_opt array;  (* the buckets *)
    initial_size: int;                        (* initial array size *)
  } 
[@@bs.deriving abstract]

#if BS then
external toOpt : 'a opt -> 'a option = "#undefined_to_opt"
external return : 'a -> 'a opt = "%identity"              
let emptyOpt = Js.undefined               
external makeSize : int -> 'a Js.undefined array = "Array" [@@bs.new]    
#else 
external toOpt : 'a -> 'a = "%identity"
let return x = Some x 
let emptyOpt = None
let makeSize s = Bs_Array.make s emptyOpt
#end

type statistics = {
  num_bindings: int;
  num_buckets: int;
  max_bucket_length: int;
  bucket_histogram: int array
}


let rec power_2_above x n =
  if x >= n then x
  else if x * 2 < x then x (* overflow *)
  else power_2_above (x * 2) n

let create0  initial_size =
  let s = power_2_above 16 initial_size in  
  t0  ~initial_size:s ~size:0
    ~buckets:(makeSize s)

let clear0 h =
  sizeSet h 0;
  let h_buckets = buckets h in 
  let len = Bs_Array.length h_buckets in
  for i = 0 to len - 1 do
    Bs_Array.unsafe_set h_buckets i  emptyOpt
  done

let reset0 h =
  let len = Bs_Array.length (buckets h) in
  let h_initial_size = initial_size h in
  if len = h_initial_size then
    clear0 h
  else begin
    sizeSet h 0;
    bucketsSet h (makeSize h_initial_size)
  end

let length0 h = size h


let rec do_bucket_iter ~f buckets = 
  match toOpt buckets with 
  | None ->
    ()
  | Some cell ->
    f (key cell)  (value cell) [@bs]; do_bucket_iter ~f (next cell)

let iter0 f h =
  let d = buckets h in
  for i = 0 to Bs_Array.length d - 1 do
    do_bucket_iter f (Bs_Array.unsafe_get d i)
  done


let rec do_bucket_fold ~f b accu =
  match toOpt b with
  | None ->
    accu
  | Some cell ->
    do_bucket_fold ~f (next cell) (f (key cell) (value cell) accu [@bs]) 

let fold0 f h init =
  let d = buckets h in
  let accu = ref init in
  for i = 0 to Bs_Array.length d - 1 do
    accu := do_bucket_fold ~f (Bs_Array.unsafe_get d i) !accu
  done;
  !accu



let rec bucket_length accu buckets = 
  match toOpt buckets with 
  | None -> accu
  | Some cell -> bucket_length (accu + 1) (next cell)

let max (m : int) n = if m > n then m else n  

let logStats0 h =
  let mbl =
    Bs_Array.foldLeft (fun[@bs] m b -> max m (bucket_length 0 b)) 0 (buckets h) in
  let histo = Bs_Array.make (mbl + 1) 0 in
  Bs_Array.iter
    (fun[@bs] b ->
       let l = bucket_length 0 b in
       Bs_Array.unsafe_set histo l (Bs_Array.unsafe_get histo l + 1)
    )
    (buckets h);
  Js.log [%obj{ num_bindings = (size h);
                num_buckets = Bs_Array.length (buckets h);
                max_bucket_length = mbl;
                bucket_histogram = histo }]


let rec filterMapInplaceBucket f h i prec bucket =
  match toOpt bucket with 
  | None ->
    begin match toOpt prec with
      | None -> Bs_Array.unsafe_set (buckets h ) i emptyOpt
      | Some cell -> nextSet  cell emptyOpt
    end
  | (Some  cell) ->
    begin match f (key cell) (value cell) [@bs] with
      | None ->
        sizeSet h (size h - 1); (* delete *)
        filterMapInplaceBucket f h i prec (next cell)
      | Some data -> (* replace *)
        begin match toOpt prec with
          | None -> Bs_Array.unsafe_set (buckets h) i  bucket 
          | Some c -> nextSet cell bucket
        end;
        valueSet cell data;
        filterMapInplaceBucket f h i bucket (next cell)
    end

let filterMapInplace0 f h =
  let h_buckets = buckets h in
  for i = 0 to Bs_Array.length h_buckets - 1 do
    filterMapInplaceBucket f h i emptyOpt (Bs_Array.unsafe_get h_buckets i)
  done
