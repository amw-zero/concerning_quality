theory ImperativeReasoning

imports AutoCorres.AutoCorres

begin

install_C_file "/Users/alexweisberger/code/recur_finance/test.c"
autocorres "/Users/alexweisberger/code/recur_finance/test.c"
print_theorems

context test begin

thm update_arr'_def

theorem 
  shows "valid (\<lambda>s :: idk. is_valid_w32 s a) (update_arr' a v) (\<lambda>rv s. is_valid_w32 s a)"
  unfolding update_arr'_def
  apply(wp)
  apply(auto)
  done
end
