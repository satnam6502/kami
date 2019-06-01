Require Import Kami.
Require Import Kami.Synthesize.
Require Import Ext.BSyntax.

Require Import Ex.ProcFetchDecode Ex.ProcThreeStage Ex.ProcFourStDec Ex.SC Ex.IsaRv32.

Require Import ExtrOcamlBasic ExtrOcamlNatInt ExtrOcamlString.
Extraction Language OCaml.

Set Extraction Optimize.
Set Extraction KeepSingleton.
Unset Extraction AutoInline.

(** Parameter instantiation *)

Definition rv32AddrSize := 32.

Section PerInstMemSize.
  Variable rv32IAddrSize: nat.

  Definition predictNextPc ty (ppc: fullType ty (SyntaxKind (Pc rv32IAddrSize))) :=
    (#ppc + $4)%kami_expr.

  Definition pinit: ProcInit rv32IAddrSize rv32DataBytes rv32RfIdx :=
    {| pcInit := Default; rfInit := Default |}.

  Definition p4st: Modules :=
    ProcFourStDec.p4st
      (rv32Fetch rv32AddrSize rv32IAddrSize)
      (rv32Dec rv32AddrSize) (rv32Exec rv32IAddrSize) predictNextPc
      (@d2ePackI _ _ _ _ _) (@d2eOpTypeI _ _ _ _ _) (@d2eDstI _ _ _ _ _) (@d2eAddrI _ _ _ _ _)
      (@d2eVal1I _ _ _ _ _) (@d2eVal2I _ _ _ _ _) (@d2eRawInstI _ _ _ _ _) (@d2eCurPcI _ _ _ _ _)
      (@d2eNextPcI _ _ _ _ _) (@d2eEpochI _ _ _ _ _)
      (@f2dPackI _ _) (@f2dRawInstI _ _) (@f2dCurPcI _ _)
      (@f2dNextPcI _ _) (@f2dEpochI _ _)
      (@e2wPackI _ _ _ _ _) (@e2wDecInstI _ _ _ _ _) (@e2wValI _ _ _ _ _)
      pinit.

  (* targetM should be your target module *)
  Definition targetM := p4st.

  (** * DON'T REMOVE OR MODIFY BELOW LINES *)

  Definition targetS := getModuleS targetM.
  Definition targetB := ModulesSToBModules targetS.

End PerInstMemSize.

(* If you are testing directly on this file with ProofGeneral or CoqIde, 
 * then use the below extraction command, instead of the one at the last line.
 *)
(* Extraction "./Ocaml/Target.ml" targetProcB. *)

(* [Target.ml] will be generated after executing the below extraction command.
 * To generate the corresponding Bluespec program, do [make] in the directory
 * [./extraction/Ocaml/]. See [./extraction/Ocaml/README.md] for details.
 *)
Extraction "./Kami/Ext/Ocaml/Target.ml" targetB.

