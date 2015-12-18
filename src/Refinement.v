Require Import Bool List String.
Require Import Lib.Struct Lib.Word Lib.CommonTactics Lib.StringBound Lib.ilist.
Require Import Syntax Semantics.
Require Import FunctionalExtensionality ProofIrrelevance Program.Equality Eqdep Eqdep_dec FMap.

Set Implicit Arguments.

Section Triples.
  Variable X Y Z: Type.

  Definition first (a : X * Y * Z) := fst (fst a) : X.
  Definition second (a : X * Y * Z) := snd (fst a) : Y.
  Definition third (a : X * Y * Z) := snd a : Z.
End Triples.

(* boolean parameter is true iff generated by a rule
   second part of LabelT is defined methods
   third part of LabelT is called methods *)
Definition LabelT := (bool * CallsT * CallsT)%type.

Section Tau.
  (* f satisfies `t2t` (for "tau2tau") if it is the identity
     operation whenever a label has no external communication *)
  Definition t2t (f: LabelT -> LabelT) :=
    forall x, second x = M.empty _ -> third x = M.empty _ -> f x = x.

  Lemma t2t_id : t2t (id (A:=LabelT)).
  Proof. unfold t2t; auto. Qed.

  Lemma t2t_compose: forall (f g: LabelT -> LabelT),
                       t2t f -> t2t g -> t2t (fun l => g (f l)).
  Proof.
    intros; unfold t2t in *; intros.
    specialize (H x); specialize (H0 x);
    rewrite H, H0; intuition.
  Qed.
End Tau.

Section LabelTrans.
  Record LabelTrans := { trs :> LabelT -> LabelT; tau2tau : t2t trs }.

  Definition idTrs := {| trs := id (A:= LabelT); tau2tau := t2t_id |}.

  Definition composeTrs (trsab trsbc: LabelTrans) :=
    {| trs := fun l => trsbc (trsab l);
       tau2tau := t2t_compose (tau2tau trsab) (tau2tau trsbc) |}.

End LabelTrans.

Section Filter.
  Variable A: Type.
  Variable filt: A -> Prop.

  (* If `Filter xs ys` is inhabited, then `ys` is filtered
     down to `xs` *)
  Inductive Filter: list A -> list A -> Prop :=
  | Nil: Filter nil nil
  | Keep a ls ls': Filter ls ls' -> ~ filt a -> Filter (a :: ls) (a :: ls')
  | Remove a ls ls': Filter ls ls' -> filt a -> Filter ls (a :: ls').

  Lemma filtNil l: Filter l nil -> l = nil.
  Proof.
    intros.
    dependent induction H; reflexivity.
  Qed.
  
End Filter.

(* a label satisfies `isTau` if the transition
   has no external communication *) 
Definition isTau (x: LabelT) :=
  second x = M.empty _ /\ third x = M.empty _.

Lemma rmEmpty_idempotent:
  forall (f: LabelTrans)
         (lca l1 l2: list LabelT),
    Filter isTau l1 lca ->
    Filter isTau l2 (map f l1) -> Filter isTau l2 (map f lca).
Proof.
  induction lca; intros; simpl in *.
  - pose proof (filtNil H); subst.
    assumption.
  - dependent destruction H; simpl in *.
    + dependent destruction H1; simpl in *.
      * constructor; intuition.
        apply (IHlca _ _ H H1).
      * constructor; intuition.
        apply (IHlca _ _ H H1).
    + constructor; intuition.
      * apply (IHlca _ _ H H1).
      * clear - H0; unfold isTau in *.
        destruct f; simpl in *.
        destruct H0 as [ ].
        specialize (tau2tau0 _ H H0).
        rewrite tau2tau0 in *.
        intuition.
Qed.

Definition mapRules (l: RuleLabelT) :=
  (match ruleMeth l with
     | Some _ => false
     | None => true
   end, dmMap l, cmMap l).

Section TraceRefines.
  (* impl = implementation
     spec = specification *)
  Definition traceRefines impl spec (f : LabelT -> LabelT) :=
    forall simp limp
           (Hclos: LtsStepClosure impl simp limp)
           filtL (Hfilt: Filter isTau filtL (map f (map mapRules limp))),
    exists sspec lspec,
      LtsStepClosure spec sspec lspec /\
      Filter isTau filtL (map mapRules lspec).
End TraceRefines.

(* `ma` refines `mb` with respect to `f` *) 
Notation "ma '<<=[' f ']' mb" :=
  (traceRefines ma mb f) (at level 100, format "ma  <<=[  f  ]  mb").

(* `ma` refines `mb` with respect to the identity transformation *)
Notation "ma '<<==' mb" :=
  (traceRefines ma mb idTrs) (at level 100, format "ma  <<==  mb").

Notation "ma '<<==>>' mb" :=
  (traceRefines ma mb idTrs /\ traceRefines mb ma idTrs)
    (at level 100, format "ma  <<==>>  mb").

Notation "{ dmMap , cmMap }" :=
  (fun x => (first x, dmMap (second x), cmMap (third x))).

Lemma id_idTrs: forall cmMap dmMap (Ht2t: t2t {dmMap, cmMap}),
                  cmMap = id -> dmMap = id ->
                  idTrs = {| trs := {dmMap, cmMap}; tau2tau :=  Ht2t |}.
Proof.
  intros; subst; unfold idTrs.
  generalize dependent Ht2t.
  match goal with
    | [ |- forall _, {| trs := ?t1; tau2tau := _ |} = {| trs := ?t2; tau2tau := _ |} ] =>
      progress replace t2 with t1
        by (apply functional_extensionality; intros; destruct x as [[ ]]; reflexivity)
  end; intros.
  assert (H: t2t_id = Ht2t) by apply proof_irrelevance; rewrite H.
  reflexivity.
Qed.

Section Relation.
  Variable rulesImp rulesSpec: list string.
  Variable dmsImp dmsSpec: list DefMethT.
  Variable imp spec: Modules.
  Variable regRel: RegsT -> RegsT -> Prop.
  Variable ruleMap: string -> string.
  Variable cmmap dmmap: CallsT -> CallsT.
  Variable initMap: regRel (initRegs (getRegInits imp)) (initRegs (getRegInits spec)).
  Variable Ht2t: t2t {dmmap, cmmap}.
  Variable allRMap:
  forall rmImp oImp lImp nImp dmImp cmImp,
    LtsStepClosure imp oImp lImp ->
    LtsStep imp rmImp oImp nImp dmImp cmImp ->
    forall oSpec,
      regRel oImp oSpec ->
      exists nSpec,
        LtsStep spec
                match rmImp with
                  | None => None
                  | Some rmImp' => Some (ruleMap rmImp')
                end oSpec nSpec (dmmap dmImp) (cmmap cmImp)
        /\ regRel (update oImp nImp) (update oSpec nSpec).

  Definition f := {| trs := {dmmap, cmmap}; tau2tau := Ht2t |}.

  Lemma fSimulation:
    forall (simp : RegsT) (limp : list RuleLabelT)
           (HclosImp: LtsStepClosure imp simp limp)
           filtL (Hfilt: Filter isTau filtL (map f (map mapRules limp))),
    exists (sspec : RegsT) (lspec : list RuleLabelT),
      LtsStepClosure spec sspec lspec
      /\ regRel simp sspec
      /\ Filter isTau filtL (map mapRules lspec).
  Proof.
    intros simpl limp HclosImp.
    dependent induction HclosImp; intros.

    - subst; exists (initRegs (getRegInits spec)); exists nil.
      split; auto.
      constructor; auto.

    - subst; specialize (IHHclosImp initMap allRMap);
      dependent destruction Hfilt; repeat (unfold mapRules, first, second, third in *);
      destruct (IHHclosImp _ Hfilt) as [sspec [lspec [HclosSpec [Hregs Hfilts]]]]; clear IHHclosImp;
      destruct (allRMap HclosImp Hlts Hregs) as [nSpec [specStep regRelSpec]]; clear allRMap;
      exists (update sspec nSpec);
      exists ((Build_RuleLabelT
                 (match rm with
                    | Some rmImp' => Some (ruleMap rmImp')
                    | None => None
                  end) (getDmsMod spec) (dmmap dNew) (getCmsMod spec) (cmmap cNew)) :: lspec);
      constructor;
      ((apply (lcLtsStep HclosSpec specStep); intuition)
         ||
         (constructor;
          [ subst; intuition |
            destruct rm; constructor; intuition ])).
  Qed.

  Theorem transMap: imp <<=[f] spec.
  Proof.
    unfold traceRefines; intros.
    destruct (fSimulation Hclos Hfilt) as [rb [lcb [Hclosb [HfactR HfactL]]]].
    eauto.
  Qed.
End Relation.

Section Props.
  Variables M N O P: Modules.

  Hypotheses (HwfM: RegsInDomain M)
             (HwfO: RegsInDomain O)
             (HdisjRegs:
                forall r : string,
                  ~ (In r (map (attrName (Kind:=Typed ConstFullT)) (getRegInits M)) /\
                     In r (map (attrName (Kind:=Typed ConstFullT)) (getRegInits O)))).

  Lemma tr_refl: M <<== M.
  Proof.
    unfold traceRefines. intros.
    exists simp. exists limp. split.
    - assumption.
    - rewrite map_id in Hfilt; assumption.
  Qed.

  Lemma tr_comb: (M <<== N) -> (O <<== P) -> ((ConcatMod M O) <<== (ConcatMod N P)).
  Proof.
    admit.
  Qed.

  Lemma tr_assoc: (ConcatMod (ConcatMod M N) O) <<==>> (ConcatMod M (ConcatMod N O)).
  Proof.
    admit.
  Qed.

End Props.