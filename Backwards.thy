theory Backwards

imports Main

begin

lemma "[] @ l = l"
  apply(induction l)
   apply(auto)
  done

lemma "A \<longrightarrow> (A \<longrightarrow> B) \<longrightarrow> B"
proof (rule impI)
  assume A
  show "(A \<longrightarrow> B) \<longrightarrow> B"
  proof (rule impI)
    assume "A \<longrightarrow> B"
    thus B using \<open>A\<close> by (rule mp)
  qed
qed

lemma 
  assumes imp_appdown: "HomePageDoesntLoad \<longrightarrow> AppIsDown"
    and hp_load: HomePageDoesntLoad
  shows "AppIsDown"
proof (rule mp[where P=HomePageDoesntLoad and Q=AppIsDown])
  from imp_appdown show "HomePageDoesntLoad \<longrightarrow> AppIsDown" by assumption
  from hp_load show HomePageDoesntLoad by assumption
qed
  
  show  "HomePageDoesntLoad \<longrightarrow> AppIsDown" by assumption
  thus "HomePageDoesntLoad" using assms(2) by assumption
  from assms have "HomePageDoesntLoad" by assumption

lemma 
  assumes HomePageDoesntLoad 
    and "HomePageDoesntLoad \<longrightarrow> AppIsDown"
  shows "AppIsDown"
  by (auto simp: assms)

lemma 
  assumes hp_load: HomePageDoesntLoad 
    and imp_appdown: "HomePageDoesntLoad \<longrightarrow> AppIsDown"
  shows "AppIsDown"
  apply(rule_tac P=HomePageDoesntLoad and Q=AppIsDown in mp)
  using imp_appdown
  apply(assumption)
  using hp_load
  apply(assumption)
  done

lemma "\<lbrakk>\<forall> x. P x \<longrightarrow> P (h x); P a \<rbrakk> \<Longrightarrow>  P(h (h a))"
  apply(frule spec)
  oops


lemma 
  assumes HomePageDoesntLoad 
    and "HomePageDoesntLoad \<longrightarrow> AppIsDown"
  shows "AppIsDown"
  using assms
  by (frule_tac P=HomePageDoesntLoad and Q="AppIsDown" in mp)


lemma 
  assumes "HomePageDoesntLoad \<longrightarrow> AppIsDown"
  and HomePageDoesntLoad 
  shows "AppIsDown"
  using assms
  by (rule mp)


definition "AppIsDown = True"
definition "HomePageDoesntLoad = True"
definition "HomePageDoesntLoadImpAppIsDown = (HomePageDoesntLoad \<longrightarrow> AppIsDown)"

lemma HomePageDoesntLoad
  unfolding HomePageDoesntLoad_def
  apply(rule TrueI)
  done

lemma "HomePageDoesntLoadImpAppIsDown \<Longrightarrow> True"
  unfolding HomePageDoesntLoadImpAppIsDown_def HomePageDoesntLoad_def AppIsDown_def
  by simp
  apply(rule impI)
  apply(assumption)
  done
  oops

lemmas HPDLImpAppDown = mp[where P=HomePageDoesntLoad and Q=AppIsDown]

lemma "HomePageDoesntLoad \<longrightarrow> AppIsDown"
  by (simp add: AppIsDown_def HomePageDoesntLoad_def)

lemma shows "AppIsDown"
  apply(rule mp)


lemma shows "AppIsDown"
  using assms
  apply(rule mp)
  done

lemma 
  assumes HomePageDoesntLoad 
    and "HomePageDoesntLoad \<longrightarrow> AppIsDown"
  shows "AppIsDown"
  using assms
  by simp


  apply(rule_tac P=HomePageDoesntLoad and Q=AppIsDown in mp)
  using assms(2)
   apply(assumption)
  using assms(1)
  apply(assumption)
  done

lemma 
  assumes NoPageLoad and "NoPageLoad \<longrightarrow> AppDown"
  shows "AppDown"
  using assms
  by auto


  using assms(1)
   apply simp
  using assms(2)
  apply simp
   apply()
  apply(rule npl)
  done

lemma assumes "NoPageLoad \<longrightarrow> AppDown"
  shows AppDown


end