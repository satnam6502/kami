Require Import Bool List String.
Require Import Lib.CommonTactics Lib.Struct Lib.StringBound Lib.ilist Lib.Word Lib.FMap.
Require Import Syntax Wf Equiv.
Require Import Semantics.

Require Import FunctionalExtensionality.

Set Implicit Arguments.

Section PhoasUT.
  Definition typeUT (k: Kind): Type := unit.
  Definition fullTypeUT := fullType typeUT.
  Definition getUT (k: FullKind): fullTypeUT k :=
    match k with
      | SyntaxKind _ => tt
      | NativeKind t c => c
    end.

  Fixpoint getCalls {retT} (a: ActionT typeUT retT) (cs: list DefMethT)
  : list DefMethT :=
    match a with
      | MCall name _ _ cont =>
        match getAttribute name cs with
          | Some dm => dm :: (getCalls (cont tt) cs)
          | None => getCalls (cont tt) cs
        end
      | Let_ _ ar cont => getCalls (cont (getUT _)) cs
      | ReadReg reg k cont => getCalls (cont (getUT _)) cs
      | WriteReg reg _ e cont => getCalls cont cs
      | IfElse ce _ ta fa cont =>
        (getCalls ta cs) ++ (getCalls fa cs) ++ (getCalls (cont tt) cs)
      | Assert_ ae cont => getCalls cont cs
      | Return e => nil
    end.

  Lemma getCalls_nil: forall {retT} (a: ActionT typeUT retT), getCalls a nil = nil.
  Proof.
    induction a; intros; simpl; intuition.
    rewrite IHa1, IHa2, (H tt); reflexivity.
  Qed.

  Lemma getCalls_sub: forall {retT} (a: ActionT typeUT retT) cs ccs,
                        getCalls a cs = ccs -> SubList ccs cs.
  Proof.
    induction a; intros; simpl; intuition; try (eapply H; eauto; fail).
    - simpl in H0.
      remember (getAttribute meth cs); destruct o.
      + pose proof (getAttribute_Some_body _ _ Heqo); subst.
        unfold SubList; intros.
        inv H0; [assumption|].
        eapply H; eauto.
      + eapply H; eauto.
    - simpl in H0; subst.
      unfold SubList; intros.
      apply in_app_or in H0; destruct H0; [|apply in_app_or in H0; destruct H0].
      + eapply IHa1; eauto.
      + eapply IHa2; eauto.
      + eapply H; eauto.
    - simpl in H; subst.
      unfold SubList; intros; inv H.
  Qed.

  Lemma getCalls_sub_name: forall {retT} (a: ActionT typeUT retT) cs ccs,
                             getCalls a cs = ccs -> SubList (namesOf ccs) (namesOf cs).
  Proof.
    induction a; intros; simpl; intuition; try (eapply H; eauto; fail).
    - simpl in H0.
      remember (getAttribute meth cs); destruct o.
      + pose proof (getAttribute_Some_body _ _ Heqo); subst.
        unfold SubList; intros.
        inv H0; [apply in_map; auto|].
        eapply H; eauto.
      + eapply H; eauto.
    - simpl in H0; subst.
      unfold SubList; intros.
      unfold namesOf in H0; rewrite map_app in H0.
      apply in_app_or in H0; destruct H0.
      + eapply IHa1; eauto.
      + rewrite map_app in H0; apply in_app_or in H0; destruct H0.
        * eapply IHa2; eauto.
        * eapply H; eauto.
    - simpl in H; subst.
      unfold SubList; intros; inv H.
  Qed.

  Section Exts.
    Definition getRuleCalls (r: Attribute (Action Void)) (cs: list DefMethT)
    : list DefMethT :=
      getCalls (attrType r typeUT) cs.

    Fixpoint getMethCalls (dms: list DefMethT) (cs: list DefMethT)
    : list DefMethT :=
      match dms with
        | nil => nil
        | dm :: dms' =>
          (getCalls (objVal (attrType dm) typeUT tt) cs)
            ++ (getMethCalls dms' cs)
      end.
  End Exts.

  Section NoCalls.
    (* Necessary condition for inlining correctness *)
    Fixpoint noCalls {retT} (a: ActionT typeUT retT) (cs: list string) :=
      match a with
        | MCall name _ _ cont =>
          if in_dec string_dec name cs then false else noCalls (cont tt) cs
        | Let_ _ ar cont => noCalls (cont (getUT _)) cs
        | ReadReg reg k cont => noCalls (cont (getUT _)) cs
        | WriteReg reg _ e cont => noCalls cont cs
        | IfElse ce _ ta fa cont => (noCalls ta cs) && (noCalls fa cs) && (noCalls (cont tt) cs)
        | Assert_ ae cont => noCalls cont cs
        | Return e => true
      end.

    Fixpoint noCallsRules (rules: list (Attribute (Action Void))) (cs: list string) :=
      match rules with
        | nil => true
        | {| attrType := r |} :: rules' => (noCalls (r typeUT) cs) && (noCallsRules rules' cs)
      end.
  
    Fixpoint noCallsDms (dms: list DefMethT) (cs: list string) :=
      match dms with
        | nil => true
        | {| attrType := {| objVal := dm |} |} :: dms' =>
          (noCalls (dm typeUT tt) cs) && (noCallsDms dms' cs)
      end.

    Fixpoint noCallsMod (m: Modules) (cs: list string) :=
      match m with
        | Mod _ rules dms => (noCallsRules rules cs) && (noCallsDms dms cs)
        | ConcatMod m1 m2 => (noCallsMod m1 cs) && (noCallsMod m2 cs)
      end.

  End NoCalls.

End PhoasUT.

Section Phoas.
  Variable type: Kind -> Type.

  Definition inlineArg {argT retT} (a: Expr type (SyntaxKind argT))
             (m: type argT -> ActionT type retT): ActionT type retT :=
    Let_ a m.

  Fixpoint getMethod (n: string) (dms: list DefMethT) :=
    match dms with
      | nil => None
      | {| attrName := mn; attrType := mb |} :: dms' =>
        if string_dec n mn then Some mb else getMethod n dms'
    end.
  
  Definition getBody (n: string) (dms: list DefMethT) (sig: SignatureT):
    option (sigT (fun x: DefMethT => objType (attrType x) = sig)) :=
    match getAttribute n dms with
      | Some a =>
        match SignatureT_dec (objType (attrType a)) sig with
          | left e => Some (existT _ a e)
          | right _ => None
        end
      | None => None
    end.

  Fixpoint inlineDms {retT} (a: ActionT type retT) (dms: list DefMethT): ActionT type retT :=
    match a with
      | MCall name sig ar cont =>
        match getBody name dms sig with
          | Some (existT dm e) =>
            appendAction (inlineArg ar ((eq_rect _ _ (objVal (attrType dm)) _ e)
                                          type))
                         (fun ak => inlineDms (cont ak) dms)
          | None => MCall name sig ar (fun ak => inlineDms (cont ak) dms)
        end
      | Let_ _ ar cont => Let_ ar (fun a => inlineDms (cont a) dms)
      | ReadReg reg k cont => ReadReg reg k (fun a => inlineDms (cont a) dms)
      | WriteReg reg _ e cont => WriteReg reg e (inlineDms cont dms)
      | IfElse ce _ ta fa cont => IfElse ce (inlineDms ta dms) (inlineDms fa dms)
                                         (fun a => inlineDms (cont a) dms)
      | Assert_ ae cont => Assert_ ae (inlineDms cont dms)
      | Return e => Return e
    end.

  Fixpoint inlineDmsRep {retT} (a: ActionT type retT) (dms: list DefMethT) (n: nat) :=
    match n with
      | O => inlineDms a dms
      | S n' => inlineDms (inlineDmsRep a dms n') dms
    end.

End Phoas.

Section Exts.
  Definition inlineToRule (r: Attribute (Action (Bit 0)))
             (dms: list DefMethT): Attribute (Action (Bit 0)) :=
    {| attrName := attrName r;
       attrType := (fun t => inlineDms (attrType r t) dms) |}.

  Definition inlineToRules (rules: list (Attribute (Action (Bit 0))))
             (dms: list DefMethT): list (Attribute (Action (Bit 0))) :=
    map (fun r => inlineToRule r dms) rules.

  Lemma inlineToRules_In:
    forall r rules dms, In r rules -> In (inlineToRule r dms) (inlineToRules rules dms).
  Proof.
    induction rules; intros; inv H.
    - left; reflexivity.
    - right; apply IHrules; auto.
  Qed.

  Lemma inlineToRules_names:
    forall rules dms, namesOf rules = namesOf (inlineToRules rules dms).
  Proof.
    induction rules; intros; simpl in *; [reflexivity|].
    f_equal; apply IHrules.
  Qed.

  Fixpoint inlineToRulesRep rules dms (n: nat) :=
    match n with
      | O => inlineToRules rules dms
      | S n' => inlineToRules (inlineToRulesRep rules dms n') dms
    end.

  Lemma inlineToRulesRep_inlineDmsRep:
    forall n rules dms,
      inlineToRulesRep rules dms n =
      map (fun ar => {| attrName := attrName ar;
                        attrType := fun t => inlineDmsRep (attrType ar t) dms n |}) rules.
  Proof.
    induction n; intros; [simpl; reflexivity|].
    simpl; rewrite IHn.
    unfold inlineToRules.
    rewrite map_map; reflexivity.
  Qed.

  Lemma inlineToRulesRep_names:
    forall n dms rules, namesOf rules = namesOf (inlineToRulesRep rules dms n).
  Proof.
    intros; rewrite inlineToRulesRep_inlineDmsRep.
    unfold namesOf; rewrite map_map; reflexivity.
  Qed.

  Definition inlineToDm (dm: DefMethT) (dms: list DefMethT): DefMethT.
  Proof.
    destruct dm as [dmn [dmt dmv]].
    refine {| attrName := dmn; attrType := {| objType := dmt; objVal := _ |} |}.
    unfold MethodT; intros ty argV.
    exact (inlineDms (dmv ty argV) dms).
  Defined.    

  Definition inlineToDms (dms tdms: list DefMethT): list DefMethT :=
    map (fun dm => inlineToDm dm tdms) dms.

  Lemma inlineToDms_In:
    forall dm dms tdms, In dm dms -> In (inlineToDm dm tdms) (inlineToDms dms tdms).
  Proof.
    intros; apply in_map with (B := DefMethT) (f := fun d => inlineToDm d tdms) in H.
    assumption.
  Qed.

  Lemma inlineToDms_names:
    forall dms tdms, namesOf dms = namesOf (inlineToDms dms tdms).
  Proof.
    induction dms; intros; intuition auto.
    simpl; f_equal.
    - destruct a as [an [ ]]; reflexivity.
    - apply IHdms.
  Qed.

  Fixpoint inlineToDmsRep (dms tdms: list DefMethT) (n: nat): list DefMethT :=
    match n with
      | O => inlineToDms dms tdms
      | S n' => inlineToDms (inlineToDmsRep dms tdms n') tdms
    end.

  Program Lemma inlineToDmsRep_inlineDmsRep:
    forall n (dms tdms: list DefMethT),
      inlineToDmsRep dms tdms n =
      map (fun (ar: Attribute (Typed MethodT))
           => {| attrName := attrName ar;
                 attrType :=
                   {| objType := objType (attrType ar);
                      objVal := fun t av => inlineDmsRep ((objVal (attrType ar)) t av) tdms n
                   |}
              |}) dms.
  Proof.
    induction n; intros.
    - simpl; unfold inlineToDms, inlineToDm.
      f_equal; extensionality dm; destruct dm as [dmn [ ]]; simpl; reflexivity.
    - simpl; rewrite IHn; unfold inlineToDms.
      rewrite map_map; reflexivity.
  Qed.

  Lemma inlineToDmsRep_names:
    forall n dms tdms, namesOf dms = namesOf (inlineToDmsRep dms tdms n).
  Proof.
    intros; rewrite inlineToDmsRep_inlineDmsRep.
    unfold namesOf; rewrite map_map; reflexivity.
  Qed.

  Definition inlineMod (m1 m2: Modules) (cdn: nat): Modules :=
    match m1, m2 with
      | Mod regs1 r1 dms1, Mod regs2 r2 dms2 =>
        Mod (regs1 ++ regs2) (inlineToRulesRep (r1 ++ r2) (dms1 ++ dms2) cdn)
            (inlineToDmsRep (complementAttrs (getCmsMod (ConcatMod m1 m2)) (dms1 ++ dms2))
                            (dms1 ++ dms2) cdn)
      | _, _ => m1 (* undefined *)
    end.

End Exts.

Fixpoint collectCalls {retK} (a: ActionT typeUT retK) (dms: list DefMethT) (cdn: nat) :=
  match cdn with
    | O => getCalls a dms
    | S n => (getCalls (inlineDmsRep a dms n) dms) ++ (collectCalls a dms n)
  end.

Lemma collectCalls_sub: forall cdn {retT} (a: ActionT typeUT retT) cs ccs,
                          collectCalls a cs cdn = ccs -> SubList ccs cs.
Proof.
  induction cdn; intros; simpl in H.
  - eapply getCalls_sub; eauto.
  - subst; unfold SubList; intros.
    apply in_app_or in H; destruct H.
    + eapply getCalls_sub; eauto.
    + eapply IHcdn; eauto.
Qed.

Inductive WfInline: forall {retK}, option string (* starting method *) ->
                                   ActionT typeUT retK -> list DefMethT -> nat -> Prop :=
| WfInlineO:
    forall {retK} odm (a: ActionT typeUT retK) dms,
      match odm with
        | Some dm => ~ In dm (namesOf (getCalls a dms))
        | None => True
      end ->
      WfInline odm a dms O
| WfInlineS:
    forall {retK} odm (a: ActionT typeUT retK) dms n,
      match odm with
        | Some dm => ~ In dm (namesOf (getCalls (inlineDmsRep a dms n) dms))
        | None => True
      end ->
      WfInline odm a dms n ->
      DisjList (namesOf (getCalls (inlineDmsRep a dms n) dms)) (namesOf (collectCalls a dms n)) ->
      WfInline odm a dms (S n).

Lemma WfInline_start:
  forall {retK} (a: ActionT typeUT retK) dm dms cdn,
    WfInline (Some dm) a dms cdn ->
    ~ In dm (namesOf (collectCalls a dms cdn)).
Proof.
  induction cdn; intros; simpl in *.
  - inv H; destruct_existT; assumption.
  - inv H; destruct_existT.
    specialize (IHcdn H5); clear H5.
    intro Hx; unfold namesOf in Hx; rewrite map_app in Hx; apply in_app_or in Hx;
    inv Hx; intuition.
Qed.

Lemma getCalls_cmMap:
  forall rules olds news dmsAll dmMap cmMap {retK} (a: ActionT typeUT retK),
    SemMod rules olds None news dmsAll dmMap cmMap ->
    MF.InDomain dmMap (namesOf (getCalls a dmsAll)) ->
    MF.InDomain (MF.restrict cmMap (namesOf dmsAll))
                (namesOf (getCalls (inlineDms a dmsAll) dmsAll)).
Proof.
  admit. (* Semantics proof *)
Qed.

Lemma getCalls_SemMod_rule_div:
  forall rules dmsAll or nr r ar dmMap1 dmMap2 cmMap1 cmMap2
         (Hrule: Some {| attrName:= r; attrType:= ar |} = getAttribute r rules)
         (Hsem: SemMod rules or (Some r) nr dmsAll
                       (MF.union dmMap1 dmMap2) (MF.union cmMap1 cmMap2))
         (Hcm: MF.Disj cmMap1 cmMap2)
         (Hdm1: exists (dms1: list DefMethT),
                  SubList dms1 dmsAll /\ MF.InDomain dmMap1 (namesOf dms1) /\
                  MF.InDomain cmMap1 ((getCmsA (ar typeUT)) ++ (getCmsM dms1)))
         (Hdm2: exists (dms2: list DefMethT),
                  SubList dms2 dmsAll /\ MF.InDomain dmMap2 (namesOf dms2) /\
                  MF.InDomain cmMap2 (getCmsM dms2)),
  exists nr1 nr2,
    MF.Disj nr1 nr2 /\ nr = MF.union nr1 nr2 /\
    SemMod rules or (Some r) nr1 dmsAll dmMap1 cmMap1 /\
    SemMod rules or None nr2 dmsAll dmMap2 cmMap2.
Proof.
  admit.
Qed.

Lemma getCalls_SemMod_meth_div:
  forall rules dmsAll or nr dmMap1 dmMap2 cmMap1 cmMap2
         (Hsem: SemMod rules or None nr dmsAll
                       (MF.union dmMap1 dmMap2) (MF.union cmMap1 cmMap2))
         (Hcm: MF.Disj cmMap1 cmMap2)
         (Hdm1: exists (dms1: list DefMethT),
                  SubList dms1 dmsAll /\ MF.InDomain dmMap1 (namesOf dms1) /\
                  MF.InDomain cmMap1 (getCmsM dms1))
         (Hdm2: exists (dms2: list DefMethT),
                  SubList dms2 dmsAll /\ MF.InDomain dmMap2 (namesOf dms2) /\
                  MF.InDomain cmMap2 (getCmsM dms2)),
  exists nr1 nr2,
    MF.Disj nr1 nr2 /\ nr = MF.union nr1 nr2 /\
    SemMod rules or None nr1 dmsAll dmMap1 cmMap1 /\
    SemMod rules or None nr2 dmsAll dmMap2 cmMap2.
Proof.
  admit.
Qed.

Lemma appendAction_SemAction:
  forall retK1 retK2 a1 a2 olds news1 news2 calls1 calls2
         (retV1: type retK1) (retV2: type retK2),
    SemAction olds a1 news1 calls1 retV1 ->
    SemAction olds (a2 retV1) news2 calls2 retV2 ->
    SemAction olds (appendAction a1 a2) (MF.union news1 news2) (MF.union calls1 calls2) retV2.
Proof.
  induction a1; intros.

  - invertAction H0; specialize (H _ _ _ _ _ _ _ _ _ H0 H1); econstructor; eauto.
    apply MF.union_add.
  - invertAction H0; specialize (H _ _ _ _ _ _ _ _ _ H0 H1); econstructor; eauto.
  - invertAction H0; specialize (H _ _ _ _ _ _ _ _ _ H2 H1); econstructor; eauto.
  - invertAction H; specialize (IHa1 _ _ _ _ _ _ _ _ H H0); econstructor; eauto.
    apply MF.union_add.
  - invertAction H0.
    simpl; remember (evalExpr e) as cv; destruct cv; dest; subst.
    + eapply SemIfElseTrue.
      * eauto.
      * eassumption.
      * eapply H; eauto.
      * rewrite MF.union_assoc; reflexivity.
      * rewrite MF.union_assoc; reflexivity.
    + eapply SemIfElseFalse.
      * eauto.
      * eassumption.
      * eapply H; eauto.
      * rewrite MF.union_assoc; reflexivity.
      * rewrite MF.union_assoc; reflexivity.

  - invertAction H; specialize (IHa1 _ _ _ _ _ _ _ _ H H0); econstructor; eauto.
  - invertAction H; econstructor; eauto.
Qed.

Lemma inlineDms_ActionEquiv:
  forall {retK} (ast: ActionT type retK) (aut: ActionT typeUT retK) dms,
    MethsEquiv type typeUT dms ->
    ActionEquiv nil ast aut ->
    ActionEquiv nil (inlineDms ast dms) (inlineDms aut dms).
Proof.
  induction 2; intros; subst; simpl; try (constructor; auto; fail).
  simpl; destruct (getBody n dms s).
  - destruct s0; subst; simpl.
    constructor; intros.
    admit. (* ActionEquiv appendAction: need "MethsEquiv type typeUT dms" *)
  - constructor; intros.
    eapply H1; eauto.
Qed.

Lemma inlineDmsRep_ActionEquiv:
  forall {retK} (ast: ActionT type retK) (aut: ActionT typeUT retK) dms cdn,
    MethsEquiv type typeUT dms ->
    ActionEquiv nil ast aut ->
    ActionEquiv nil (inlineDmsRep ast dms cdn) (inlineDmsRep aut dms cdn).
Proof.
  induction cdn; intros; simpl in *; apply inlineDms_ActionEquiv; auto.
Qed.

Lemma getCalls_SemAction:
  forall {retK} (aut: ActionT typeUT retK) (ast: ActionT type retK)
         ectx (Hequiv: ActionEquiv ectx ast aut) dms cdms
         olds news calls retV,
    getCalls aut dms = cdms ->
    SemAction olds ast news calls retV ->
    MF.InDomain calls (namesOf cdms).
Proof.
  admit. (* Semantics proof *)
Qed.

Inductive WfmAction {ty}: list string -> forall {retT}, ActionT ty retT -> Prop :=
| WfmMCall:
    forall ll name sig ar {retT} cont (Hnin: ~ In name ll),
      (forall t, WfmAction (name :: ll) (cont t)) ->
      WfmAction ll (MCall (lretT:= retT) name sig ar cont)
| WfmLet:
    forall ll {argT retT} ar cont,
      (forall t, WfmAction ll (cont t)) ->
      WfmAction ll (Let_ (lretT':= argT) (lretT:= retT) ar cont)
| WfmReadReg:
    forall ll {retT} reg k cont,
      (forall t, WfmAction ll (cont t)) ->
      WfmAction ll (ReadReg (lretT:= retT) reg k cont)
| WfmWriteReg:
    forall ll {writeT retT} reg e cont,
      WfmAction ll cont ->
      WfmAction ll (WriteReg (k:= writeT) (lretT:= retT) reg e cont)
| WfmIfElse:
    forall ll {retT1 retT2} ce ta fa cont,
      WfmAction ll (appendAction (retT1:= retT1) (retT2:= retT2) ta cont) ->
      WfmAction ll (appendAction (retT1:= retT1) (retT2:= retT2) fa cont) ->
      WfmAction ll (IfElse ce ta fa cont)
| WfmAssert:
    forall ll {retT} e cont,
      WfmAction ll cont ->
      WfmAction ll (Assert_ (lretT:= retT) e cont)
| WfmReturn:
    forall ll {retT} (e: Expr ty (SyntaxKind retT)), WfmAction ll (Return e).

Hint Constructors WfmAction.

Inductive WfmActionRep {ty} (dms: list DefMethT):
  list string -> forall {retT}, ActionT ty retT -> nat -> Prop :=
| WfmInlineO: forall ll {retT} (a: ActionT ty retT),
                WfmAction ll a -> WfmAction ll (inlineDms a dms) ->
                WfmActionRep dms ll a O
| WfmInlineS: forall ll n {retT} (a: ActionT ty retT),
                WfmActionRep dms ll a n ->
                WfmAction ll (inlineDmsRep a dms (S n)) ->
                WfmActionRep dms ll a (S n).

Lemma WfmAction_init_sub {ty}:
  forall {retK} (a: ActionT ty retK) ll1
         (Hwfm: WfmAction ll1 a) ll2
         (Hin: forall k, In k ll2 -> In k ll1),
    WfmAction ll2 a.
Proof.
  induction 1; intros; simpl; intuition.

  econstructor; eauto; intros.
  apply H0; eauto.
  intros; inv H1; intuition.
Qed.

Lemma WfmAction_append_1' {ty}:
  forall {retT2} a3 ll,
    WfmAction ll a3 ->
    forall {retT1} (a1: ActionT ty retT1) (a2: ty retT1 -> ActionT ty retT2),
      a3 = appendAction a1 a2 -> WfmAction ll a1.
Proof.
  induction 1; intros.

  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    econstructor; eauto.
  - destruct a1; simpl in *; try discriminate.
    + inv H1; destruct_existT; econstructor; eauto.
    + inv H1; destruct_existT; econstructor.
  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    econstructor; eauto.
  - destruct a1; simpl in *; try discriminate; inv H0; destruct_existT.
    econstructor; eauto.
  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    constructor.
    + eapply IHWfmAction1; eauto; apply appendAction_assoc.
    + eapply IHWfmAction2; eauto; apply appendAction_assoc.
  - destruct a1; simpl in *; try discriminate; inv H0; destruct_existT.
    econstructor; eauto.
  - destruct a1; simpl in *; try discriminate.
Qed.

Lemma WfmAction_append_1 {ty}:
  forall {retT1 retT2} (a1: ActionT ty retT1) (a2: ty retT1 -> ActionT ty retT2) ll,
    WfmAction ll (appendAction a1 a2) ->
    WfmAction ll a1.
Proof. intros; eapply WfmAction_append_1'; eauto. Qed.

Lemma WfmAction_append_2' : let ty := type in
  forall {retT2} a3 ll,
    WfmAction ll a3 ->
    forall {retT1} (a1: ActionT ty retT1) (a2: ty retT1 -> ActionT ty retT2),
      a3 = appendAction a1 a2 ->
      forall t, WfmAction ll (a2 t).
Proof.
  induction 1; intros.

  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    apply WfmAction_init_sub with (ll1:= meth :: ll); [|intros; right; assumption].
    eapply H0; eauto.
  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    + eapply H0; eauto.
    + apply H.
  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    eapply H0; eauto.
  - destruct a1; simpl in *; try discriminate; inv H0; destruct_existT.
    eapply IHWfmAction; eauto.
  - destruct a1; simpl in *; try discriminate; inv H1; destruct_existT.
    eapply IHWfmAction1; eauto.
    apply appendAction_assoc.
  - destruct a1; simpl in *; try discriminate; inv H0; destruct_existT.
    eapply IHWfmAction; eauto.
  - destruct a1; simpl in *; try discriminate.

    Grab Existential Variables.
    { exact (evalConstFullT (getDefaultConstFull _)). }
    { exact (evalConstFullT (getDefaultConstFull _)). }
    { exact (evalConstT (getDefaultConst _)). }
Qed.

Lemma WfmAction_append_2:
  forall {retT1 retT2} (a1: ActionT type retT1) (a2: type retT1 -> ActionT type retT2) ll,
    WfmAction ll (appendAction a1 a2) ->
    forall t, WfmAction ll (a2 t).
Proof. intros; eapply WfmAction_append_2'; eauto. Qed.

Lemma WfmAction_cmMap:
  forall {retK} olds (a: ActionT type retK) news calls retV ll
         (Hsem: SemAction olds a news calls retV)
         (Hwfm: WfmAction ll a)
         lb (Hin: In lb ll),
    M.find lb calls = None.
Proof.
  induction 1; intros; simpl; subst; intuition idtac; inv Hwfm; destruct_existT.

  - rewrite MF.find_add_2.
    { apply IHHsem; eauto.
      specialize (H2 mret); eapply WfmAction_init_sub; eauto.
      intros; right; assumption.
    }
    { intro Hx; subst; elim Hnin; assumption. }
  - eapply IHHsem; eauto.
  - eapply IHHsem; eauto.
  - eapply IHHsem; eauto.
  - assert (M.find lb calls1 = None).
    { eapply IHHsem1; eauto.
      eapply WfmAction_append_1; eauto.
    }
    assert (M.find lb calls2 = None).
    { eapply IHHsem2; eauto.
      eapply WfmAction_append_2; eauto.
    }
    rewrite MF.find_union; rewrite H, H0; reflexivity.
  - assert (M.find lb calls1 = None).
    { eapply IHHsem1; eauto.
      eapply WfmAction_append_1; eauto.
    }
    assert (M.find lb calls2 = None).
    { eapply IHHsem2; eauto.
      eapply WfmAction_append_2; eauto.
    }
    rewrite MF.find_union; rewrite H, H0; reflexivity.
  - eapply IHHsem; eauto.
Qed.

Lemma WfmAction_append_3':
  forall {retT2} a3 ll,
    WfmAction ll a3 ->
    forall {retT1} (a1: ActionT type retT1) (a2: type retT1 -> ActionT type retT2),
      a3 = appendAction a1 a2 ->
      forall olds news1 news2 calls1 calls2 retV1 retV2,
      SemAction olds a1 news1 calls1 retV1 ->
      SemAction olds (a2 retV1) news2 calls2 retV2 ->
      MF.Disj calls1 calls2.
Proof.
  induction 1; intros; simpl; intuition idtac; destruct a1; simpl in *; try discriminate.
  unfold MF.Disj; intros lb.
  
  - inv H1; destruct_existT.
    invertAction H2; specialize (H x).
    specialize (H0 _ _ _ _ eq_refl _ _ _ _ _ _ _ H1 H3 lb).
    destruct H0; [|right; assumption].
    destruct (string_dec lb meth); [subst; right|left].
    + pose proof (WfmAction_append_2 _ _ H retV1).
      apply MF.P.F.not_find_in_iff.
      eapply WfmAction_cmMap; eauto.
    + apply MF.P.F.not_find_in_iff.
      apply MF.P.F.not_find_in_iff in H0.
      rewrite MF.find_add_2; auto.
  - inv H1; destruct_existT; invertAction H2; eapply H0; eauto.
  - inv H1; destruct_existT; invertAction H2; apply MF.Disj_empty_1.
  - inv H1; destruct_existT; invertAction H2; eapply H0; eauto.
  - inv H0; destruct_existT; invertAction H1; eapply IHWfmAction; eauto.
  - inv H1; destruct_existT.
    invertAction H2.
    destruct (evalExpr e); dest; subst.
    + specialize (@IHWfmAction1 _ (appendAction a1_1 a) a2 (appendAction_assoc _ _ _)).
      eapply IHWfmAction1; eauto.
      eapply appendAction_SemAction; eauto.
    + specialize (@IHWfmAction2 _ (appendAction a1_2 a) a2 (appendAction_assoc _ _ _)).
      eapply IHWfmAction2; eauto.
      eapply appendAction_SemAction; eauto.
    
  - inv H0; destruct_existT; invertAction H1; eapply IHWfmAction; eauto.
Qed.

Lemma WfmAction_append_3:
  forall {retT1 retT2} (a1: ActionT type retT1) (a2: type retT1 -> ActionT type retT2) ll,
    WfmAction ll (appendAction a1 a2) ->
    forall olds news1 news2 calls1 calls2 retV1 retV2,
      SemAction olds a1 news1 calls1 retV1 ->
      SemAction olds (a2 retV1) news2 calls2 retV2 ->
      MF.Disj calls1 calls2.
Proof. intros; eapply WfmAction_append_3'; eauto. Qed.

Lemma WfmAction_init:
  forall {retK} (a: ActionT type retK) ll
         (Hwfm: WfmAction ll a),
    WfmAction nil a.
Proof. intros; eapply WfmAction_init_sub; eauto; intros; inv H. Qed.

Lemma WfmAction_MCall:
  forall {retK} olds a news calls (retV: type retK) dms
         (Hsem: SemAction olds a news calls retV)
         (Hwfm: WfmAction dms a),
    MF.complement calls dms = calls.
Proof.
  induction 1; intros; inv Hwfm; destruct_existT.

  - rewrite MF.complement_add_2 by assumption; f_equal.
    apply IHHsem.
    specialize (H2 mret).
    apply (WfmAction_init_sub H2 dms).
    intros; right; assumption.
  - eapply IHHsem; eauto.
  - eapply IHHsem; eauto.
  - eapply IHHsem; eauto.
  - rewrite MF.complement_union; f_equal.
    + eapply IHHsem1; eauto.
      eapply WfmAction_append_1; eauto.
    + eapply IHHsem2; eauto.
      eapply WfmAction_append_2; eauto.
  - rewrite MF.complement_union; f_equal.
    + eapply IHHsem1; eauto.
      eapply WfmAction_append_1; eauto.
    + eapply IHHsem2; eauto.
      eapply WfmAction_append_2; eauto.
  - eapply IHHsem; eauto.
  - apply MF.complement_empty.
Qed.

(* TODO: semantics stuff; move to Semantics.v *)
Lemma SemMod_dmMap_sig:
  forall rules or rm nr dms dmn dsig dm dmMap cmMap
         (Hdms: NoDup (namesOf dms))
         (Hin: In (dmn :: {| objType := dsig; objVal := dm |})%struct dms)
         (Hsem: SemMod rules or rm nr dms dmMap cmMap)
         (Hdmn: M.find dmn dmMap <> None),
  exists dv, M.find dmn dmMap = Some {| objType := dsig; objVal := dv |}.
Proof.
  admit. (* Semantics proof *)
Qed.

(* TODO: semantics stuff; move to Semantics.v *)
Lemma SemMod_getCalls:
  forall rules olds news dmsAll dmMap cmMap {retK} (a: ActionT typeUT retK) cdms
         (Hcdms: cdms = getCalls a dmsAll)
         (Hsem: SemMod rules olds None news dmsAll dmMap cmMap)
         (Hdm: MF.InDomain dmMap (namesOf cdms)),
    MF.InDomain cmMap (namesOf (getCalls (inlineDms a dmsAll) dmsAll)).
Proof.
  admit. (* Semantics proof *)
Qed.

Section Preliminaries.

  Lemma inlineDms_prop:
    forall olds retK (at1: ActionT type retK) (au1: ActionT typeUT retK)
           (Hequiv: ActionEquiv nil at1 au1)
           dmsAll rules
           news newsA (HnewsA: MF.Disj news newsA)
           dmMap cmMap cmMapA (HcmA: MF.Disj cmMap cmMapA)
           (retV: type retK) cdms,
      WfmAction nil at1 ->
      getCalls au1 dmsAll = cdms ->
      
      SemAction olds at1 newsA cmMapA retV ->
      NoDup (namesOf dmsAll) ->
      dmMap = MF.restrict cmMapA (namesOf cdms) -> (* label matches *)
      SemMod rules olds None news dmsAll dmMap cmMap ->
      SemAction olds (inlineDms at1 dmsAll) (MF.union news newsA)
                (MF.union cmMap (MF.complement cmMapA (namesOf cdms)))
                retV.
  Proof.
    induction 1; intros; simpl in *.

    - inv H1; destruct_existT.
      inv H3; destruct_existT.
      remember (getBody n dmsAll s) as odm; destruct odm.

      + destruct s0; generalize dependent HSemAction; subst; intros.
        rewrite <-Eqdep.Eq_rect_eq.eq_rect_eq.
        econstructor; eauto.

        unfold getBody in Heqodm.
        remember (getAttribute n dmsAll) as dmAttr; destruct dmAttr; [|discriminate].
        destruct (SignatureT_dec _ _); [|discriminate].
        generalize dependent HSemAction; inv Heqodm; inv e; intros.

        pose proof (getAttribute_Some_name _ _ HeqdmAttr); subst.

        (* dividing SemMod (a + calls) first *)
        specialize (H10 mret).
        rewrite MF.restrict_add in H6 by (left; reflexivity).
        match goal with
          | [H: SemMod _ _ _ _ _ (M.add ?ak ?av ?dM) _ |- _] =>
            assert (M.add ak av dM = MF.union (M.add ak av (M.empty _)) dM)
              by (rewrite MF.union_add, MF.union_empty_L; reflexivity)
        end.
        
        rewrite H1 in H6; clear H1.
        replace (MF.restrict calls (namesOf (a :: getCalls (cont2 tt) dmsAll))) with
        (MF.restrict calls (namesOf (getCalls (cont2 tt) dmsAll))) in H6.
        Focus 2. (* map proof begins *)
        pose proof (WfmAction_MCall HSemAction H10).
        apply MF.complement_restrict_nil in H1.
        replace (a :: getCalls (cont2 tt) dmsAll)
        with (app [a] (getCalls (cont2 tt) dmsAll)) by reflexivity.
        unfold namesOf; rewrite map_app; rewrite MF.restrict_app.
        simpl in H1; simpl; rewrite H1.
        rewrite MF.union_empty_L; reflexivity.
        (* map proof ends *)

        match goal with
          | [ |- SemAction _ _ _ ?cM _ ] =>
            replace cM with
            (MF.union cmMap (MF.complement calls (namesOf (getCalls (cont2 tt) dmsAll))))
        end.
        Focus 2. (* map proof begins *)
        f_equal; rewrite MF.complement_add_1 by intuition.
        pose proof (getCalls_SemAction (H mret tt) dmsAll eq_refl HSemAction).
        apply MF.restrict_InDomain_itself in H1; apply MF.restrict_complement_nil in H1.
        rewrite H1.
        rewrite <-MF.complement_SubList with (l1:= namesOf (getCalls (cont2 tt) dmsAll))
          by (unfold SubList; intros; right; assumption).
        rewrite H1; rewrite MF.complement_empty; reflexivity.
        (* map proof ends *)
        
        apply MF.Disj_comm, MF.Disj_add_2 in HcmA; destruct HcmA as [HcmA _].
        match goal with
          | [H: SemMod _ _ _ _ _ (MF.union ?m1 ?m2) _ |- _] =>
            assert (MF.Disj m1 m2)
        end.
        { pose proof (WfmAction_MCall HSemAction H10).
          apply MF.Disj_comm, MF.Disj_restrict.
          clear -H1; apply MF.complement_restrict_nil in H1.

          (* manual map proof *)
          unfold MF.restrict, MF.Disj in *; intros.
          destruct (string_dec k a); [subst|].
          { left; apply MF.F.P.F.not_find_in_iff.
            destruct (Map.find a calls); intuition auto.
            inv H1.
          }
          { right; intro Hx; elim n; clear n.
            apply MF.F.P.F.add_in_iff in Hx; destruct Hx; [auto|].
            apply MF.F.P.F.empty_in_iff in H; elim H.
          }
        }
        
        pose proof (SemMod_div H6 H1); dest; subst; clear H6 H1.
        pose proof (SemMod_meth_singleton HeqdmAttr H4 H8); clear H8.

        (* reordering arguments to apply appendAction_SemAction *)
        rewrite <-MF.union_assoc with (m1:= x).
        rewrite <-MF.union_assoc with (m1:= x1).

        apply appendAction_SemAction with (retV1:= mret); auto.

        eapply H0; eauto.
        * apply MF.Disj_comm, MF.Disj_union_2, MF.Disj_comm in HnewsA; assumption.
        * apply MF.Disj_union_2, MF.Disj_comm in HcmA; assumption.
        * eapply WfmAction_init; eauto.

      + unfold getBody in Heqodm.
        remember (getAttribute n dmsAll) as mat; destruct mat.

        * destruct (SignatureT_dec _ _); [discriminate|].
          exfalso; elim n0; clear n0.
          pose proof (getAttribute_Some_name _ _ Heqmat); subst.
          pose proof (getAttribute_Some_body _ _ Heqmat).
          destruct a as [an [ ]]; pose proof (SemMod_dmMap_sig _ _ H4 H1 H6); simpl in *.
          do 2 rewrite MF.find_add_1 in H2.
          specialize (H2 (opt_discr _)); dest.
          clear -H2; inv H2; reflexivity.

        * assert (~ In n (namesOf (getCalls (cont2 tt) dmsAll))).
          { pose proof (getAttribute_None _ _ Heqmat).
            intro Hx; elim H1; clear H1.
            pose proof (@getCalls_sub_name _ (cont2 tt) dmsAll _ eq_refl).
            apply H1; auto.
          }

          econstructor; eauto.
          { instantiate (1:= MF.union (MF.complement
                                         calls
                                         (namesOf (getCalls (cont2 tt) dmsAll)))
                                      cmMap).
            instantiate (1:= mret).

            rewrite MF.complement_add_2 by assumption.
            rewrite <-MF.union_add.
            apply MF.union_comm.
            rewrite <-MF.complement_add_2 by assumption.
            apply MF.Disj_complement; auto.
          }
          { rewrite MF.union_comm with (m2:= cmMap)
              by (apply MF.Disj_comm, MF.Disj_complement, MF.Disj_comm;
                  apply MF.Disj_comm, MF.Disj_add_2 in HcmA; intuition auto).

            eapply H0; eauto.
            { apply MF.Disj_comm, MF.Disj_add_2 in HcmA; destruct HcmA as [HcmA _].
              apply MF.Disj_comm; auto.
            }
            { specialize (H10 mret); eapply WfmAction_init; eauto. }
            { p_equal H6.
              rewrite MF.restrict_add_not by assumption.
              reflexivity.
            }
          }

    - inv H1; destruct_existT.
      inv H3; destruct_existT.
      econstructor; eauto.

    - inv H1; destruct_existT.
      inv H3; destruct_existT.
      econstructor; eauto.

    - inv H0; destruct_existT.
      inv H2; destruct_existT.
      econstructor; eauto.

      + instantiate (1:= MF.union news newRegs).
        rewrite MF.union_comm by assumption.
        rewrite MF.union_add; f_equal.
        apply MF.union_comm.
        apply MF.Disj_comm, MF.Disj_add_2 in HnewsA; intuition.
      + eapply IHHequiv; eauto.
        apply MF.Disj_comm, MF.Disj_add_2 in HnewsA; destruct HnewsA.
        apply MF.Disj_comm; auto.

    - inv H2; destruct_existT.
      inv H4; destruct_existT.

      + rewrite MF.restrict_union in H7.
        match goal with
          | [H: SemMod _ _ _ _ _ (MF.union ?m1 ?m2) _ |- _] =>
            assert (MF.Disj m1 m2)
        end.
        { apply MF.Disj_restrict, MF.Disj_comm, MF.Disj_restrict, MF.Disj_comm.
          pose proof (WfmAction_append_3 _ H12 HAction HSemAction).
          assumption.
        }

        pose proof (SemMod_div H7 H2); clear H2 H7; dest; subst.
        eapply SemIfElseTrue.

        * assumption.
        * eapply IHHequiv1; [| | |reflexivity|exact HAction| | |exact H7].
          { apply MF.Disj_union_1, MF.Disj_comm, MF.Disj_union_1, MF.Disj_comm in HnewsA;
            assumption.
          }
          { apply MF.Disj_union_1, MF.Disj_comm, MF.Disj_union_1, MF.Disj_comm in HcmA;
            assumption.
          }
          { eapply WfmAction_append_1; eauto. }
          { assumption. }
          { pose proof (getCalls_SemAction Hequiv1 dmsAll eq_refl HAction).
            apply MF.restrict_InDomain_itself in H3.
            rewrite <-H3 at 1; rewrite MF.restrict_comm, MF.restrict_SubList; [reflexivity|].
            unfold namesOf; rewrite map_app.
            apply SubList_app_1, SubList_refl.
          }
        * eapply H1; [| | |reflexivity|exact HSemAction| |reflexivity|].
          { apply MF.Disj_union_2, MF.Disj_comm, MF.Disj_union_2, MF.Disj_comm in HnewsA;
            eassumption.
          }
          { apply MF.Disj_union_2, MF.Disj_comm, MF.Disj_union_2, MF.Disj_comm in HcmA;
            eassumption.
          }
          { eapply WfmAction_append_2; eauto. }
          { assumption. }
          { instantiate (1:= tt).
            p_equal H8.
            pose proof (getCalls_SemAction (H0 r1 tt) dmsAll eq_refl HSemAction).
            apply MF.restrict_InDomain_itself in H3.
            rewrite <-H3 at 1; rewrite MF.restrict_comm, MF.restrict_SubList; [reflexivity|].
            unfold namesOf; do 2 rewrite map_app.
            do 2 apply SubList_app_2; apply SubList_refl.
          }
        * do 2 rewrite <-MF.union_assoc with (m1:= x); f_equal.
          do 2 rewrite MF.union_assoc; f_equal.
          apply MF.union_comm.
          apply MF.Disj_union_1, MF.Disj_comm, MF.Disj_union_2, MF.Disj_comm in HnewsA.
          assumption.
        * pose proof (getCalls_SemAction Hequiv1 dmsAll eq_refl HAction).
          pose proof (getCalls_SemAction (H0 r1 tt) dmsAll eq_refl HSemAction).

          rewrite MF.complement_union.
          apply MF.restrict_InDomain_itself in H3; apply MF.restrict_complement_nil in H3.
          apply MF.restrict_InDomain_itself in H6; apply MF.restrict_complement_nil in H6.

          unfold DefMethT in *.
          unfold namesOf; rewrite map_app.
          rewrite MF.complement_app; rewrite MF.complement_comm.
          rewrite MF.complement_app with (m:= calls2); rewrite map_app.
          rewrite MF.complement_app with (m:= calls2).
          unfold namesOf in H3; rewrite H3.
          unfold namesOf in H6; rewrite H6.
          repeat rewrite MF.complement_empty.
          repeat (try rewrite MF.union_empty_L; try rewrite MF.union_empty_R).
          reflexivity.

      + rewrite MF.restrict_union in H7.
        match goal with
          | [H: SemMod _ _ _ _ _ (MF.union ?m1 ?m2) _ |- _] =>
            assert (MF.Disj m1 m2)
        end.
        { apply MF.Disj_restrict, MF.Disj_comm, MF.Disj_restrict, MF.Disj_comm.
          pose proof (WfmAction_append_3 _ H16 HAction HSemAction).
          assumption.
        }

        pose proof (SemMod_div H7 H2); clear H2 H7; dest; subst.
        eapply SemIfElseFalse.

        * assumption.
        * eapply IHHequiv2; [| | |reflexivity|exact HAction| | |exact H7].
          { apply MF.Disj_union_1, MF.Disj_comm, MF.Disj_union_1, MF.Disj_comm in HnewsA;
            assumption.
          }
          { apply MF.Disj_union_1, MF.Disj_comm, MF.Disj_union_1, MF.Disj_comm in HcmA;
            assumption.
          }
          { eapply WfmAction_append_1; eauto. }
          { assumption. }
          { pose proof (getCalls_SemAction Hequiv2 dmsAll eq_refl HAction).
            apply MF.restrict_InDomain_itself in H3.
            rewrite <-H3 at 1; rewrite MF.restrict_comm, MF.restrict_SubList; [reflexivity|].
            unfold namesOf; do 2 rewrite map_app.
            apply SubList_app_2, SubList_app_1; apply SubList_refl.
          }
        * eapply H1; [| | |reflexivity|exact HSemAction| |reflexivity|].
          { apply MF.Disj_union_2, MF.Disj_comm, MF.Disj_union_2, MF.Disj_comm in HnewsA;
            eassumption.
          }
          { apply MF.Disj_union_2, MF.Disj_comm, MF.Disj_union_2, MF.Disj_comm in HcmA;
            eassumption.
          }
          { eapply WfmAction_append_2; eauto. }
          { assumption. }
          { instantiate (1:= tt).
            p_equal H8.
            pose proof (getCalls_SemAction (H0 r1 tt) dmsAll eq_refl HSemAction).
            apply MF.restrict_InDomain_itself in H3.
            rewrite <-H3 at 1; rewrite MF.restrict_comm, MF.restrict_SubList; [reflexivity|].
            unfold namesOf; do 2 rewrite map_app.
            do 2 apply SubList_app_2; apply SubList_refl.
          }
        * do 2 rewrite <-MF.union_assoc with (m1:= x); f_equal.
          do 2 rewrite MF.union_assoc; f_equal.
          apply MF.union_comm.
          apply MF.Disj_union_1, MF.Disj_comm, MF.Disj_union_2, MF.Disj_comm in HnewsA.
          assumption.
        * pose proof (getCalls_SemAction Hequiv2 dmsAll eq_refl HAction).
          pose proof (getCalls_SemAction (H0 r1 tt) dmsAll eq_refl HSemAction).

          rewrite MF.complement_union.
          apply MF.restrict_InDomain_itself in H3; apply MF.restrict_complement_nil in H3.
          apply MF.restrict_InDomain_itself in H6; apply MF.restrict_complement_nil in H6.

          unfold DefMethT in *.
          unfold namesOf; rewrite map_app.
          rewrite MF.complement_app with (m:= calls1); rewrite map_app.
          rewrite MF.complement_app with (m:= calls1).
          rewrite MF.complement_comm with (m:= calls1).
          do 2 rewrite MF.complement_app with (m:= calls2).
          unfold namesOf in H3; rewrite H3.
          unfold namesOf in H6; rewrite H6.
          repeat rewrite MF.complement_empty.
          repeat (try rewrite MF.union_empty_L; try rewrite MF.union_empty_R).
          reflexivity.

    - inv H0; destruct_existT.
      inv H2; destruct_existT.
      econstructor; eauto.

    - inv H0; destruct_existT.
      inv H2; destruct_existT.
      pose proof (SemMod_empty_inv H5); dest; subst.
      econstructor; eauto.

  Qed.

  Lemma inlineToRules_prop:
    forall olds r (ar: Action (Bit 0))
           (Hequiv: ActionEquiv nil (ar type) (ar typeUT))
           dmsAll rules
           news newsA (HnewsA: MF.Disj news newsA)
           dmMap cmMap cmMapA (HcmA: MF.Disj cmMap cmMapA) cdms,
      WfmAction nil (ar type) ->
      In {| attrName := r; attrType := ar |} rules -> NoDup (namesOf rules) ->
      getCalls (ar typeUT) dmsAll = cdms ->

      SemMod rules olds (Some r) newsA dmsAll (M.empty _) cmMapA ->
      NoDup (namesOf dmsAll) ->
      MF.restrict cmMapA (namesOf cdms) = dmMap -> (* label matches *)
      SemMod rules olds None news dmsAll dmMap cmMap ->
      SemMod (inlineToRules rules dmsAll) olds (Some r)
             (MF.union news newsA) dmsAll (M.empty _)
             (MF.union cmMap (MF.complement cmMapA (namesOf cdms))).
  Proof.
    intros; inv H3.
    pose proof (SemMod_empty_inv HSemMod); dest; subst.
    
    econstructor.
    - pose proof (inlineToRules_In _ _ dmsAll HInRule); simpl in H2.
      eassumption.
    - assert (ar = ruleBody); subst.
      { clear -H0 H1 HInRule.
        generalize dependent r; generalize dependent ar; generalize dependent ruleBody.
        induction rules; intros; [inv H0|].
        inv H0.
        { inv HInRule.
          { inv H; reflexivity. }
          { inv H1; elim H3.
            apply in_map with (B:= string) (f:= (fun a => attrName a)) in H.
            simpl in H; assumption.
          }
        }
        { inv HInRule.
          { inv H1; elim H3.
            apply in_map with (B:= string) (f:= (fun a => attrName a)) in H.
            simpl in H; assumption.
          }
          { inv H1; eapply IHrules; eauto. }
        }
      }

      simpl; eapply inlineDms_prop with (newsA:= news0) (cmMapA:= calls); eauto.
      + apply MF.Disj_union_1 in HnewsA; eauto.
      + apply MF.Disj_union_1 in HcmA; eauto.
      + rewrite MF.union_empty_R in H6; eassumption.
        
    - apply SemMod_empty.
    - apply MF.Disj_empty_2.
    - apply MF.Disj_empty_2.
    - do 2 rewrite MF.union_empty_R; reflexivity.
    - do 2 rewrite MF.union_empty_R; reflexivity.
  Qed.

  Lemma inlineToRulesRep_prop':
    forall olds cdn r (ar: Action (Bit 0))
           (Hequiv: ActionEquiv nil (ar type) (ar typeUT))
           dmsAll (Hmequiv: MethsEquiv type typeUT dmsAll)
           rules news newsA (HnewsA: MF.Disj news newsA)
           dmMap cmMap cmMapA (HcmA: MF.Disj cmMap cmMapA) cdms,
      WfmActionRep dmsAll nil (ar type) cdn ->
      WfInline None (ar typeUT) dmsAll (S cdn) ->
      In {| attrName := r; attrType := ar |} rules -> NoDup (namesOf rules) ->
      collectCalls (ar typeUT) dmsAll cdn = cdms ->

      SemMod rules olds (Some r) newsA dmsAll (M.empty _) cmMapA ->
      NoDup (namesOf dmsAll) ->
      SemMod rules olds None news dmsAll dmMap cmMap ->
      dmMap = MF.restrict (MF.union cmMap cmMapA) (namesOf cdms) ->
      SemMod (inlineToRulesRep rules dmsAll cdn) olds (Some r)
             (MF.union news newsA) dmsAll (M.empty _)
             (MF.complement (MF.union cmMap cmMapA) (namesOf cdms)).
  Proof.
    induction cdn; intros.

    - simpl.
      pose proof (SemMod_rule_singleton (in_NoDup_getAttribute _ _ _ H1 H2) H2 H4).
      simpl in *.
      inv H; destruct_existT.

      assert (cmMap = MF.complement cmMap (namesOf (getCalls (ar typeUT) dmsAll))).
      { inv H0; destruct_existT; simpl in H15.
        pose proof (SemMod_getCalls (ar typeUT) eq_refl H6 (@MF.restrict_InDomain _ _ _)).
        pose proof (MF.restrict_InDomain_DisjList _ _ _ H H15).
        apply MF.restrict_complement_itself in H0; auto.
      }

      rewrite MF.restrict_union in H6.
      assert (M.empty _ = MF.restrict cmMap (namesOf (getCalls (ar typeUT) dmsAll))).
      { rewrite MF.complement_restrict_nil; auto. }

      rewrite MF.complement_union; rewrite <-H; clear H.
      rewrite <-H3 in H6; rewrite MF.union_empty_L in H6; clear H3.

      eapply inlineToRules_prop; eauto.

    - simpl; simpl in H3; subst.

      (* Reallocate dmMaps and news *)
      unfold namesOf in H6; rewrite map_app in H6;
      rewrite MF.restrict_app in H6; apply SemMod_div in H6;
      [|apply MF.Disj_DisjList_restrict; inv H0; inv H11; destruct_existT; assumption].
      destruct H6 as [news2 [news1 [cmMap2 [cmMap1 H6]]]].

      dest; subst.

      (* Reallocate news *)
      rewrite <-MF.union_assoc with (m1:= news2).

      (* Reallocate cmMaps *)
      match goal with
        | [ |- SemMod _ _ _ _ _ _ ?cm ] =>
          replace cm with
          (MF.union (MF.complement
                       cmMap2
                       (namesOf (collectCalls (ar typeUT) dmsAll cdn))) 
                    (MF.complement
                       (MF.union
                          (MF.complement
                             cmMap1
                             (namesOf (collectCalls (ar typeUT) dmsAll cdn)))
                          (MF.complement
                             cmMapA
                             (namesOf (collectCalls (ar typeUT) dmsAll cdn))))
                       (namesOf (getCalls (inlineDmsRep (ar typeUT) dmsAll cdn) dmsAll))))
      end.
      Focus 2. (* "replace" subgoal begins *)
      unfold namesOf; repeat rewrite map_app; repeat rewrite MF.complement_app.
      repeat rewrite MF.complement_union.
      rewrite MF.union_assoc; do 2 f_equal.

      inv H0; destruct_existT; clear H11.
      inv H14; destruct_existT; clear H8.
      pose proof (SemMod_getCalls (inlineDmsRep (ar typeUT) dmsAll cdn)
                                  eq_refl H9 (@MF.restrict_InDomain _ _ _)).
      assert (cmMap2 = MF.complement
                         cmMap2 (namesOf (getCalls (inlineDmsRep (ar typeUT) dmsAll cdn)
                                                   dmsAll))).
      { simpl in H16; unfold namesOf in H16.
        rewrite map_app in H16; apply DisjList_app_1 in H16.
        pose proof (MF.restrict_InDomain_DisjList _ _ _ H0 H16).
        rewrite MF.restrict_complement_itself by assumption; reflexivity.
      }
      rewrite H6 at 1; clear H6.
      rewrite MF.complement_comm; reflexivity.
      (* "replace" subgoal ends *)
      
      eapply inlineToRules_prop; try assumption; try reflexivity.

      + instantiate (1:= fun t => inlineDmsRep (ar t) dmsAll cdn).
        eapply inlineDmsRep_ActionEquiv; eauto.
      + apply MF.Disj_union; [assumption|].
        apply MF.Disj_comm, MF.Disj_union_1, MF.Disj_comm in HnewsA; assumption.
      + apply MF.Disj_union.
        * apply MF.Disj_complement, MF.Disj_comm, MF.Disj_complement, MF.Disj_comm; assumption.
        * apply MF.Disj_complement, MF.Disj_comm, MF.Disj_complement, MF.Disj_comm.
          apply MF.Disj_comm, MF.Disj_union_1, MF.Disj_comm in HcmA; assumption.
      + inv H; destruct_existT.
        inv H13; destruct_existT; auto.
      + rewrite inlineToRulesRep_inlineDmsRep.
        clear -H1.
        induction rules; [inv H1|].
        inv H1; [left; reflexivity|].
        right; apply IHrules; auto.
      + rewrite <-inlineToRulesRep_names; assumption.
      + reflexivity.
      + rewrite <-MF.complement_union.
        eapply IHcdn; try assumption; try reflexivity.

        * assumption.
        * apply MF.Disj_comm, MF.Disj_union_2, MF.Disj_comm in HnewsA; assumption.
        * apply MF.Disj_comm, MF.Disj_union_2, MF.Disj_comm in HcmA; assumption.
        * inv H; destruct_existT; assumption.
        * inv H0; destruct_existT; assumption.
        * assumption.
        * pose proof (getCalls_cmMap (inlineDmsRep (ar typeUT) dmsAll cdn) H9).
          specialize (H6 (@MF.restrict_InDomain _ _ _)).

          assert (MF.restrict cmMap2 (namesOf (collectCalls (ar typeUT) dmsAll cdn)) =
                  M.empty _).
          { inv H0; destruct_existT.
            simpl in H17; unfold namesOf in H17;
            rewrite map_app in H17; apply DisjList_app_2 in H17.
            rewrite <-MF.restrict_SubList with (m:= cmMap2) (l2:= namesOf dmsAll).
            eapply MF.restrict_InDomain_DisjList; eauto.
            apply SubList_map; eapply collectCalls_sub; eauto.
          }
          do 2 rewrite MF.restrict_union in H10.
          unfold namesOf in H8.
          unfold DefMethT in H10; rewrite H8 in H10.

          rewrite MF.union_empty_L in H10.
          rewrite <-MF.restrict_union in H10.
          assumption.

      + apply SemMod_rules_free with (rules1:= rules).
        pose proof (getCalls_cmMap (inlineDmsRep (ar typeUT) dmsAll cdn) H9).
        specialize (H6 (@MF.restrict_InDomain _ _ _)).

        assert (MF.restrict cmMap2 (namesOf (collectCalls (ar typeUT) dmsAll cdn)) =
                M.empty _).
        { inv H0; destruct_existT.
          simpl in H17; unfold namesOf in H17;
          rewrite map_app in H17; apply DisjList_app_2 in H17.
          rewrite <-MF.restrict_SubList with (m:= cmMap2) (l2:= namesOf dmsAll).
          eapply MF.restrict_InDomain_DisjList; eauto.
          apply SubList_map; eapply collectCalls_sub; eauto.
        }
        pose proof (MF.restrict_complement_itself _ _ H8); rewrite H11; clear H8 H11.

        assert (MF.restrict
                  cmMap2 (namesOf (getCalls (inlineDmsRep (ar typeUT) dmsAll cdn) dmsAll))
                = M.empty _).
        { inv H0; destruct_existT.
          simpl in H17; unfold namesOf in H17;
          rewrite map_app in H17; apply DisjList_app_1 in H17.
          rewrite <-MF.restrict_SubList with (m:= cmMap2) (l2:= namesOf dmsAll).
          eapply MF.restrict_InDomain_DisjList; eauto.
          apply SubList_map; eapply getCalls_sub; eauto.
        }
        do 2 rewrite MF.restrict_union in H9.
        unfold DefMethT in H9; unfold namesOf in H8; rewrite H8 in H9.

        rewrite MF.union_empty_L in H9.
        rewrite <-MF.restrict_union in H9.
        rewrite <-MF.complement_union.

        inv H0; inv H16; destruct_existT.
        apply DisjList_comm in H21.
        rewrite MF.restrict_complement_DisjList by assumption.
        assumption.
  Qed.

  Lemma inlineToRulesRep_prop:
    forall olds cdn r (ar: Action (Bit 0))
           (Hequiv: ActionEquiv nil (ar type) (ar typeUT))
           dmsAll (Hmequiv: MethsEquiv type typeUT dmsAll)
           rules news dmMap cmMap cdms,
      WfmActionRep dmsAll nil (ar type) cdn ->
      WfInline None (ar typeUT) dmsAll (S cdn) ->
      In {| attrName := r; attrType := ar |} rules -> NoDup (namesOf rules) ->
      collectCalls (ar typeUT) dmsAll cdn = cdms ->

      SemMod rules olds (Some r) news dmsAll dmMap cmMap ->
      NoDup (namesOf dmsAll) ->
      dmMap = MF.restrict cmMap (namesOf cdms) ->
      SemMod (inlineToRulesRep rules dmsAll cdn) olds (Some r)
             news dmsAll (M.empty _) (MF.complement cmMap (namesOf cdms)).
  Proof.
    intros.
    replace dmMap with (MF.union (M.empty _) dmMap) in H4 by auto.

    apply SemMod_div in H4; [|auto].
    destruct H4 as [news2 [news1 [cmMap2 [cmMap1 H4]]]]; dest; subst.

    rewrite MF.union_comm with (m1:= news2) by assumption.
    rewrite MF.union_comm with (m1:= cmMap2) by assumption.
    rewrite MF.union_comm with (m1:= cmMap2) in H11 by assumption.
    eapply inlineToRulesRep_prop'; eauto.
    - apply MF.Disj_comm; assumption.
    - apply MF.Disj_comm; assumption.
    - apply MF.Disj_empty_1.
  Qed.

  Lemma inlineToDms_prop:
    forall olds dmn dsig (dargV: type (arg dsig)) (dretV: type (ret dsig)) (ad: MethodT dsig)
           (Hequiv: ActionEquiv nil (ad type dargV) (ad typeUT tt))
           dmsAll dmsConst (Hmequiv: MethsEquiv type typeUT dmsConst)
           rules news newsA (HnewsA: MF.Disj news newsA)
           dmMap dmMapA cmMap cmMapA (HcmA: MF.Disj cmMap cmMapA) cdms,
      WfmAction nil (ad type dargV) ->
      Some {| attrName := dmn; attrType := {| objType := dsig; objVal := ad |} |}
      = getAttribute dmn dmsAll ->
      NoDup (namesOf dmsAll) -> NoDup (namesOf dmsConst) ->
      getCalls (ad typeUT tt) dmsConst = cdms ->

      dmMapA = M.add dmn {| objType := dsig; objVal := (dargV, dretV) |} (M.empty _) ->
      SemMod rules olds None newsA dmsAll dmMapA cmMapA ->
      MF.restrict cmMapA (namesOf cdms) = dmMap -> (* label matches *)
      SemMod rules olds None news dmsConst dmMap cmMap ->
      SemMod rules olds None
             (MF.union news newsA) (inlineToDms dmsAll dmsConst) dmMapA
             (MF.union cmMap (MF.complement cmMapA (namesOf cdms))).
  Proof.
    intros; subst.
    inv H5; [exfalso; eapply MF.add_empty_neq; eauto|].

    destruct meth as [methName [methT methBody]]; simpl in *.

    assert (dmn = methName /\ dsig = methT /\ dm2 = M.empty _).
    { clear -HNew HDefs; pose proof HDefs.
      apply @Equal_val with (k:= methName) in H.
      destruct (string_dec methName dmn); [subst|].
      { do 2 rewrite MF.find_add_1 in H.
        inv H; destruct_existT.
        repeat split; auto.
        apply M.leibniz; unfold M.Equal; intros k.
        destruct (string_dec k dmn); [subst|].
        { rewrite HNew; rewrite MF.F.P.F.empty_o; reflexivity. }
        { apply @Equal_val with (k:= k) in HDefs.
          do 2 rewrite MF.find_add_2 in HDefs by assumption.
          auto.
        }
      }
      { rewrite MF.find_add_1 in H; rewrite MF.find_add_2 in H by assumption.
        rewrite MF.F.P.F.empty_o in H; inv H.
      }
    }
    dest; subst.

    assert (dargV = argV /\ dretV = retV).
    { clear -HDefs; apply @Equal_val with (k:= methName) in HDefs.
      do 2 rewrite MF.find_add_1 in HDefs.
      apply opt_some_eq, typed_eq in HDefs; inv HDefs; auto.
    }
    dest; subst; clear HDefs.

    (* TODO: better to extract a lemma *)
    assert (ad = methBody).
    { clear -HIn H0 H1.
      pose proof (getAttribute_Some_body _ _ H0); clear H0.
      induction dmsAll; [inv HIn|].
      inv H1; inv HIn.
      { inv H.
        { inv H0; destruct_existT; reflexivity. }
        { elim H3; simpl.
          apply in_map with (B:= string) (f:= @attrName _) in H0; assumption.
        }
      }
      { inv H.
        { elim H3; simpl.
          apply in_map with (B:= string) (f:= @attrName _) in H0; assumption.
        }
        { apply IHdmsAll; auto. }
      }
    }
    subst.

    inv HSemMod; [|exfalso; eapply MF.add_empty_neq; eauto].

    eapply SemAddMeth.
    - eapply inlineToDms_In; eauto.
    - eapply inlineDms_prop with (newsA:= news0) (cmMapA:= calls);
        try assumption; try reflexivity.
      + eassumption.
      + apply MF.Disj_union_1 in HnewsA; exact HnewsA.
      + apply MF.Disj_union_1 in HcmA; exact HcmA.
      + assumption.
      + eassumption.
      + rewrite MF.union_empty_R in H7; eassumption.
    - eapply SemEmpty; eauto.
    - apply MF.Disj_empty_2.
    - apply MF.Disj_empty_2.
    - do 2 rewrite MF.union_empty_R; reflexivity.
    - do 2 rewrite MF.union_empty_R; reflexivity.
    - reflexivity.
    - reflexivity.
  Qed.

  Lemma inlineToDmsRep_prop':
    forall olds cdn dmn dsig (dargV: type (arg dsig)) (dretV: type (ret dsig)) (ad: MethodT dsig)
           (Hequiv: ActionEquiv nil (ad type dargV) (ad typeUT tt))
           dmsAll dmsConst (Hmequiv: MethsEquiv type typeUT dmsConst)
           rules news newsA (HnewsA: MF.Disj news newsA)
           dmMap dmMapA cmMap cmMapA (HcmA: MF.Disj cmMap cmMapA) cdms,
      WfmActionRep dmsConst nil (ad type dargV) cdn ->
      WfInline (Some dmn) (ad typeUT tt) dmsConst (S cdn) ->
      Some {| attrName := dmn; attrType := {| objType := dsig; objVal := ad |} |}
      = getAttribute dmn dmsAll ->
      NoDup (namesOf dmsAll) -> NoDup (namesOf dmsConst) ->
      collectCalls (ad typeUT tt) dmsConst cdn = cdms ->

      dmMapA = M.add dmn {| objType := dsig; objVal := (dargV, dretV) |} (M.empty _) ->
      SemMod rules olds None newsA dmsAll dmMapA cmMapA ->
      SemMod rules olds None news dmsConst dmMap cmMap ->
      dmMap = MF.restrict (MF.union cmMap cmMapA) (namesOf cdms) ->
      SemMod rules olds None
             (MF.union news newsA) (inlineToDmsRep dmsAll dmsConst cdn) dmMapA
             (MF.complement (MF.union cmMap cmMapA) (namesOf cdms)).
  Proof.
    induction cdn; intros.

    - simpl in *.
      rewrite H5 in H6; pose proof (SemMod_meth_singleton H1 H2 H6); simpl in H9.

      assert (cmMap = MF.complement cmMap (namesOf cdms)).
      { subst; pose proof (SemMod_getCalls _ eq_refl H7 (@MF.restrict_InDomain _ _ _)).
        inv H0; destruct_existT.
        pose proof (MF.restrict_InDomain_DisjList _ _ _ H4 H15); simpl in H0.
        apply MF.restrict_complement_itself in H0; auto.
      }
      assert (M.empty _ = MF.restrict cmMap (namesOf cdms)).
      { rewrite MF.complement_restrict_nil; auto. }

      rewrite MF.complement_union; rewrite <-H10.
      rewrite MF.restrict_union in H8; rewrite <-H11 in H8; clear H10 H11.
      rewrite MF.union_empty_L in H8.

      subst; eapply inlineToDms_prop; eauto. 
      inv H; destruct_existT; assumption.

    - simpl; simpl in H4; subst.

      (* Reallocate dmMaps and news *)
      unfold namesOf in H7; rewrite map_app in H7;
      rewrite MF.restrict_app in H7; apply SemMod_div in H7;
      [|apply MF.Disj_DisjList_restrict; inv H0; inv H11; destruct_existT; assumption].
      destruct H7 as [news2 [news1 [cmMap2 [cmMap1 H7]]]].

      dest; subst.

      (* Reallocate news *)
      rewrite <-MF.union_assoc with (m1:= news2).

      (* Reallocate cmMaps *)
      match goal with
        | [ |- SemMod _ _ _ _ _ _ ?cm ] =>
          replace cm with
          (MF.union (MF.complement
                       cmMap2
                       (namesOf (collectCalls (ad typeUT tt) dmsConst cdn)))
                    (MF.complement
                       (MF.union
                          (MF.complement
                             cmMap1
                             (namesOf (collectCalls (ad typeUT tt) dmsConst cdn)))
                          (MF.complement
                             cmMapA
                             (namesOf (collectCalls (ad typeUT tt) dmsConst cdn))))
                       (namesOf (getCalls (inlineDmsRep (ad typeUT tt) dmsConst cdn) dmsConst))))
      end.
      Focus 2. (* "replace" subgoal begins *)
      unfold namesOf; repeat rewrite map_app; repeat rewrite MF.complement_app.
      repeat rewrite MF.complement_union.
      rewrite MF.union_assoc; do 2 f_equal.

      inv H0; destruct_existT; clear H11.
      inv H14; destruct_existT; clear H8.
      pose proof (SemMod_getCalls (inlineDmsRep (ad typeUT tt) dmsConst cdn)
                                  eq_refl H9 (@MF.restrict_InDomain _ _ _)).
      assert (cmMap2 = MF.complement
                         cmMap2 (namesOf (getCalls (inlineDmsRep (ad typeUT tt) dmsConst cdn)
                                                   dmsConst))).
      { simpl in H16; unfold namesOf in H16.
        rewrite map_app in H16; apply DisjList_app_1 in H16.
        pose proof (MF.restrict_InDomain_DisjList _ _ _ H0 H16).
        rewrite MF.restrict_complement_itself by assumption; reflexivity.
      }
      rewrite H5 at 1; clear H5.
      apply MF.complement_comm.
      (* "replace" subgoal ends *)

      eapply inlineToDms_prop; try assumption; try reflexivity.

      + instantiate (1:= fun t av => inlineDmsRep (ad t av) dmsConst cdn).
        eapply inlineDmsRep_ActionEquiv; eauto.
      + apply MF.Disj_union; [assumption|].
        apply MF.Disj_comm, MF.Disj_union_1, MF.Disj_comm in HnewsA; assumption.
      + apply MF.Disj_union.
        * apply MF.Disj_complement, MF.Disj_comm, MF.Disj_complement, MF.Disj_comm; assumption.
        * apply MF.Disj_complement, MF.Disj_comm, MF.Disj_complement, MF.Disj_comm.
          apply MF.Disj_comm, MF.Disj_union_1, MF.Disj_comm in HcmA; assumption.
      + inv H; destruct_existT.
        inv H13; destruct_existT; auto.
      + rewrite inlineToDmsRep_inlineDmsRep.
        clear -H1; induction dmsAll; [inv H1|]; simpl in H1.
        simpl; destruct (string_dec dmn a).
        * clear -H1; subst; destruct a as [an [ ]].
          simpl in *; inv H1; destruct_existT.
          reflexivity.
        * apply IHdmsAll; auto.
      + rewrite <-inlineToDmsRep_names; assumption.
      + reflexivity.
      + rewrite <-MF.complement_union.
        eapply IHcdn; try assumption; try reflexivity.

        * assumption.
        * apply MF.Disj_comm, MF.Disj_union_2, MF.Disj_comm in HnewsA; assumption.
        * apply MF.Disj_comm, MF.Disj_union_2, MF.Disj_comm in HcmA; assumption.
        * inv H; destruct_existT; assumption.
        * inv H0; destruct_existT; assumption.
        * assumption.
        * pose proof (getCalls_cmMap (inlineDmsRep (ad typeUT tt) dmsConst cdn) H9).
          specialize (H5 (@MF.restrict_InDomain _ _ _)).

          assert (MF.restrict cmMap2 (namesOf (collectCalls (ad typeUT tt) dmsConst cdn)) =
                  M.empty _).
          { inv H0; destruct_existT.
            simpl in H17; unfold namesOf in H17;
            rewrite map_app in H17; apply DisjList_app_2 in H17.
            rewrite <-MF.restrict_SubList with (m:= cmMap2) (l2:= namesOf dmsConst).
            eapply MF.restrict_InDomain_DisjList; eauto.
            apply SubList_map; eapply collectCalls_sub; eauto.
          }
          do 2 rewrite MF.restrict_union in H10.
          unfold namesOf in H8.
          unfold DefMethT in H10; rewrite H8 in H10.

          rewrite MF.union_empty_L in H10.
          rewrite <-MF.restrict_union in H10.
          assumption.

      + pose proof (getCalls_cmMap (inlineDmsRep (ad typeUT tt) dmsConst cdn) H9).
        specialize (H5 (@MF.restrict_InDomain _ _ _)).

        assert (MF.restrict cmMap2 (namesOf (collectCalls (ad typeUT tt) dmsConst cdn)) =
                M.empty _).
        { inv H0; destruct_existT.
          simpl in H17; unfold namesOf in H17;
          rewrite map_app in H17; apply DisjList_app_2 in H17.
          rewrite <-MF.restrict_SubList with (m:= cmMap2) (l2:= namesOf dmsConst).
          eapply MF.restrict_InDomain_DisjList; eauto.
          apply SubList_map; eapply collectCalls_sub; eauto.
        }
        pose proof (MF.restrict_complement_itself _ _ H8); rewrite H11; clear H8 H11.

        assert (MF.restrict cmMap2 (namesOf (getCalls (inlineDmsRep (ad typeUT tt) dmsConst cdn)
                                                   dmsConst)) = M.empty _).
        { inv H0; destruct_existT.
          simpl in H17; unfold namesOf in H17;
          rewrite map_app in H17; apply DisjList_app_1 in H17.
          rewrite <-MF.restrict_SubList with (m:= cmMap2) (l2:= namesOf dmsConst).
          eapply MF.restrict_InDomain_DisjList; eauto.
          apply SubList_map; eapply getCalls_sub; eauto.
        }
        do 2 rewrite MF.restrict_union in H9.
        unfold DefMethT in H9; unfold namesOf in H8; rewrite H8 in H9.

        rewrite MF.union_empty_L in H9.
        rewrite <-MF.restrict_union in H9.
        rewrite <-MF.complement_union.

        inv H0; inv H16; destruct_existT.
        apply DisjList_comm in H21.
        rewrite MF.restrict_complement_DisjList by assumption.
        assumption.
  Qed.

  Lemma inlineToDmsRep_prop:
    forall olds cdn dmn dsig (dargV: type (arg dsig)) (dretV: type (ret dsig)) (ad: MethodT dsig)
           (Hequiv: ActionEquiv nil (ad type dargV) (ad typeUT tt))
           dmsAll (Hmequiv: MethsEquiv type typeUT dmsAll)
           rules news dmMap dmMapA cmMap cdms,
      WfmActionRep dmsAll nil (ad type dargV) cdn ->
      WfInline (Some dmn) (ad typeUT tt) dmsAll (S cdn) ->
      Some {| attrName := dmn; attrType := {| objType := dsig; objVal := ad |} |}
      = getAttribute dmn dmsAll ->
      NoDup (namesOf dmsAll) ->
      collectCalls (ad typeUT tt) dmsAll cdn = cdms ->

      dmMapA = M.add dmn {| objType := dsig; objVal := (dargV, dretV) |} (M.empty _) ->
      dmMap = MF.restrict cmMap (namesOf cdms) ->
      SemMod rules olds None news dmsAll (MF.union dmMap dmMapA) cmMap ->
      SemMod rules olds None news (inlineToDmsRep dmsAll dmsAll cdn)
             dmMapA (MF.complement cmMap (namesOf cdms)).
  Proof.
    intros; subst.

    apply SemMod_div in H6.

    - destruct H6 as [news1 [news2 [cmMap1 [cmMap2 H6]]]]; dest; subst.
      eapply inlineToDmsRep_prop'; eauto.

    - clear -H0; inv H0; destruct_existT.
      pose proof (WfInline_start H5); clear -H.
      unfold MF.Disj; intros.

      do 2 rewrite MF.P.F.not_find_in_iff.
      destruct (string_dec k dmn);
        [|right; rewrite MF.find_add_2 by assumption; reflexivity].
      subst; left.
      apply MF.restrict_not_in; auto.
  Qed.

End Preliminaries.

Section InlineModFacts.

  Definition LabelT := (option string * CallsT * CallsT)%type.

  Inductive Inlinable (cdn: nat) (rules: list (Attribute (Action Void)))
            (dmsAll: list DefMethT)
  : list string (* fired dms *) -> list string (* executed dms *) ->
    option string -> CallsT -> CallsT -> Prop :=
  | InlinableEmpty: Inlinable cdn rules dmsAll nil nil None (M.empty _) (M.empty _)
  | InlinableRule:
      forall r ar,
        In {| attrName := r; attrType := ar |} rules ->
        forall pfdms pedms pdm pcm,
          Inlinable cdn rules dmsAll pfdms pedms None pdm pcm ->
          forall dm cm (edms: list DefMethT),
            collectCalls (ar typeUT) dmsAll cdn = edms ->
            dm = MF.restrict cm (namesOf edms) -> (* inlining condition *)
            (* SemMod divisible condition *)
            MF.InDomain cm ((getCmsA (ar typeUT)) ++ (getCmsM edms)) ->
            MF.Disj dm pdm -> MF.Disj cm pcm ->
            MF.complement cm pedms = cm -> MF.complement pcm (namesOf edms) = pcm ->
            Inlinable cdn rules dmsAll pfdms ((namesOf edms) ++ pedms)
                      (Some r) (MF.union dm pdm) (MF.union cm pcm)
  | InlinableMeth:
      forall dmn dsig dmb,
        Some {| attrName := dmn; attrType := {| objType := dsig; objVal := dmb |} |}
        = getAttribute dmn dmsAll ->
      forall pfdms pedms pdm pcm,
        Inlinable cdn rules dmsAll pfdms pedms None pdm pcm ->
        forall fdm dargV dretV dm cm (edms: list DefMethT),
          fdm = M.add dmn {| objType := dsig; objVal := (dargV, dretV) |} (M.empty _) ->
          dm = MF.restrict cm (namesOf edms) -> (* inlining condition *)
          (* SemMod divisible condition *)
          MF.InDomain cm ((getCmsA (dmb typeUT tt)) ++ (getCmsM edms)) ->
          MF.Disj fdm pdm -> MF.Disj dm pdm -> MF.Disj cm pcm ->
          MF.complement cm pedms = cm -> MF.complement pcm (dmn :: (namesOf edms)) = pcm ->
          Inlinable cdn rules dmsAll (dmn :: pfdms) ((dmn :: (namesOf edms)) ++ pedms)
                    None (MF.union (MF.union fdm dm) pdm) (MF.union cm pcm).
  
  Variables (regs1 regs2: list RegInitT)
            (r1 r2: list (Attribute (Action Void)))
            (dms1 dms2: list DefMethT).

  Variable countdown: nat.

  Definition m1 := Mod regs1 r1 dms1.
  Definition m2 := Mod regs2 r2 dms2.

  Definition cm := ConcatMod m1 m2.
  Definition im := @inlineMod m1 m2 countdown.

  Lemma inlineMod_correct:
    forall cdn rules (Hrequiv: RulesEquiv type typeUT rules)
           dmsAll (Hmequiv: MethsEquiv type typeUT dmsAll)
           fdms edms rm dmMap cmMap
           (Hsep: Inlinable cdn rules dmsAll fdms edms rm dmMap cmMap)
           (Hcdn: cdn = countdown) (Hrules: rules = r1 ++ r2) (HdmsAll: dmsAll = dms1 ++ dms2)
           or nr,
      NoDup (namesOf (r1 ++ r2)) -> NoDup (namesOf (dms1 ++ dms2)) ->

      (* MF.OnDomain dmMap (namesOf fdms) -> *)
      (* MF.InDomain dmMap (namesOf edms) -> *)
      (* dmMap = MF.restrict cmMap edms -> *)
      SemMod (getRules cm) or rm nr (getDmsBodies cm) dmMap cmMap ->
      SemMod (getRules im) or rm nr (getDmsBodies im)
             (MF.restrict dmMap fdms)
             (MF.complement cmMap edms).
  Proof.
    induction 3; intros; simpl in *.

    - subst; apply SemMod_empty_inv in H1; dest; subst.
      apply SemMod_empty.

    - subst cdn rules dmsAll.
      assert (exists nr1 nr2,
                SemMod (r1 ++ r2) or (Some r) nr1 (dms1 ++ dms2) dm cm0 /\
                SemMod (r1 ++ r2) or None nr2 (dms1 ++ dms2) pdm pcm /\
                MF.Disj nr1 nr2 /\ nr = MF.union nr1 nr2).
      { clear -H9.
        (* TODOTODOTODO *)
        admit. }
      clear H9; destruct H10 as [rnr [pnr ?]]; dest; subst nr.

      replace (MF.restrict (MF.union dm pdm) pfdms) with
      (MF.union (M.empty _) (MF.restrict pdm pfdms)) by admit.
      (* D(dm) in edms -> D(dm) not in pedms -> D(dm) not in pfdms since pfdms <= pedms *)

      rewrite MF.complement_union.
      do 2 rewrite MF.complement_app; rewrite H5.
      rewrite MF.complement_comm; rewrite H6.

      apply SemMod_merge_rule.

      + apply SemMod_dms_free with (dms1:= dms1 ++ dms2).
        eapply inlineToRulesRep_prop.

        * instantiate (1:= ar). admit. (* from RulesEquiv *)
        * assumption.
        * admit. (* TODO: construct conditions *)
        * admit. (* TODO: construct conditions *)
        * assumption.
        * assumption.
        * assumption.
        * eassumption.
        * assumption.
        * assumption.

      + apply IHHsep; auto.
      + assumption.
      + apply MF.Disj_empty_1.
      + apply MF.Disj_complement, MF.Disj_comm, MF.Disj_complement, MF.Disj_comm; assumption.

    - admit.
  Qed.

End InlineModFacts.

 