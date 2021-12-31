theory ImperativeReasoning

imports AutoCorres.AutoCorres

begin

install_C_file "/Users/alexweisberger/code/concerning_quality/test.c"
autocorres[heap_abs_syntax] "/Users/alexweisberger/code/concerning_quality/test.c"

context test begin

thm update_arr'_def
thm main'_def

value "array_addrs (PTR(32 word) (symbol_table ''c'')) 3"

definition "array_mem_valid s a = (is_valid_w32 s a \<and> is_valid_w32 s (ptr_add a 1))"

theorem
  "valid
    (\<lambda>s. array_mem_valid s a)
    (update_arr' a v)
    (\<lambda>_ s. (array_mem_valid s a) \<and> s[ptr_add a 1] = v)"
  unfolding update_arr'_def and array_mem_valid_def
  apply(wp)
  apply(auto simp: fun_upd_def)
  done

theorem
  "valid
    (\<lambda>s. array_mem_valid s a \<and> s = s0)
    (update_arr' a v)
    (\<lambda>_ s. (array_mem_valid s a) \<and> s = s0[(ptr_add a 1) := v])"
  unfolding update_arr'_def and array_mem_valid_def
  apply(wp)
  apply(auto simp: fun_upd_def)
  done

(* Main is also valid *)

find_theorems is_valid_w32

theorem
  "validNF
    (\<lambda>s. True)
    main'
    (\<lambda>_ s. True)"
  unfolding update_arr'_def and main'_def
  apply(wp)
   apply(auto simp: fun_upd_def)
  oops


theorem
  "validNF
    (\<lambda>s. array_mem_valid s a)
    (update_arr' a v)
    (\<lambda>_ s. (array_mem_valid s a) \<and> s[ptr_add a 1] = v)"
  unfolding update_arr'_def and array_mem_valid_def
  apply(wp)
  apply(simp add: fun_upd_def)
  done

(* theorem - array access is never out of bounds *)

end

end
