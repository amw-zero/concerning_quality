theory ExecutionReasoning

imports AutoCorres.AutoCorres

begin

install_C_file "/Users/alexweisberger/code/concerning_quality/response_cache.c"
autocorres[heap_abs_syntax] "/Users/alexweisberger/code/concerning_quality/response_cache.c"
                  
print_theorems

context response_cache begin


thm request_data'_def

value "lifted_globals"
thm request_data'_def
thm order_from_server'_def

(* Data is only fetched if it isn't already present in the cache *)
(* theorem "request_data' *)

theorem 
  "valid 
    (\<lambda>s. True) 
    (request_data' i)
    (\<lambda>rv s. rv = order_from_server' i)"

end

end