{-# LANGUAGE TemplateHaskellQuotes #-}

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- The code before modification is BSD3 licensed, (c) 2010-2011 Patrick Bahr.

{- |
Copyright   :  (c) 2010-2011 Patrick Bahr
               (c) 2023 Yamada Ryo
License     :  MPL-2.0 (see the file LICENSE)
Maintainer  :  ymdfield@outlook.jp
Stability   :  experimental
Portability :  portable
-}
module Control.Effect.Class.TH.HFunctor where

import Control.Effect.Class.HFunctor (HFunctor, hfmap)
import Control.Monad (replicateM, (<=<))
import Data.Maybe (catMaybes)
import Language.Haskell.TH (
    Body (NormalB),
    Clause (Clause),
    Con (ForallC, GadtC, InfixC, NormalC, RecC),
    Cxt,
    Dec (DataD, InstanceD, NewtypeD),
    DerivClause,
    Exp,
    Info (TyConI),
    Name,
    Pat (ConP, VarP, WildP),
    Q,
    Quote (..),
    TyVarBndr (..),
    Type (AppT, ConT, ForallT, SigT, VarT),
    appE,
    conE,
    funD,
    reify,
    varE,
 )
import Language.Haskell.TH.Syntax (StrictType)

{- |
Derive an instance of @HFunctor@ for a type constructor of any higher-order
kind taking at least two arguments.
-}
makeHFunctor :: Name -> Q [Dec]
makeHFunctor fname = do
    Just dInfo <- abstractNewtype <$> reify fname
    deriveHFunctor dInfo

{- |
Derive an instance of @HFunctor@ for a type constructor of any higher-order
kind taking at least two arguments, from @DataInfo@.
-}
deriveHFunctor :: DataInfo flag -> Q [Dec]
deriveHFunctor (DataInfo _cxt name args constrs _deriving) = do
    let args' = init args
        fArg = VarT . tyVarName $ last args'
        argNames = map (VarT . tyVarName) (init args')
        complType = foldl AppT (ConT name) argNames
        classType = AppT (ConT ''HFunctor) complType
    constrs' <- mapM (mkPatAndVars . isFarg fArg <=< normalConExp) constrs
    hfmapDecl <- funD 'hfmap (map hfmapClause constrs')
    return [mkInstanceD [] classType [hfmapDecl]]
  where
    isFarg fArg (constr, args_, ty) = (constr, map (`containsType'` getBinaryFArg fArg ty) args_)
    filterVar _ nonFarg [] x = nonFarg x
    filterVar farg _ [depth] x = farg depth x
    filterVar _ _ _ _ = error "functor variable occurring twice in argument type"
    filterVars args_ varNs farg nonFarg = zipWith (filterVar farg nonFarg) args_ varNs
    mkCPat constr varNs = ConP constr [] $ map mkPat varNs
    mkPat = VarP
    mkPatAndVars :: (Name, [[t]]) -> Q (Q Exp, Pat, (t -> Q Exp -> c) -> (Q Exp -> c) -> [c], Bool, [Q Exp], [(t, Name)])
    mkPatAndVars (constr, args_) =
        do
            varNs <- newNames (length args_) "x"
            return
                ( conE constr
                , mkCPat constr varNs
                , \f g -> filterVars args_ varNs (\d x -> f d (varE x)) (g . varE)
                , not (all null args_)
                , map varE varNs
                , catMaybes $ filterVars args_ varNs (curry Just) (const Nothing)
                )
    hfmapClause (con, pat, vars', hasFargs, _, _) =
        do
            fn <- newName "f"
            let f = varE fn
                fp = if hasFargs then VarP fn else WildP
                vars = vars' (\d x -> iter d [|fmap|] f `appE` x) id
            body <- foldl appE con vars
            return $ Clause [fp, pat] (NormalB body) []

-- * Utilify functions

-- | A reified information of a datatype.
data DataInfo flag = DataInfo
    { dataCxt :: Cxt
    , dataName :: Name
    , dataTyVars :: [TyVarBndr flag]
    , dataCons :: [Con]
    , dataDerivings :: [DerivClause]
    }

{- |
This function abstracts away @newtype@ declaration, it turns them into
@data@ declarations.
-}
abstractNewtype :: Info -> Maybe (DataInfo ())
abstractNewtype = \case
    TyConI (NewtypeD cxt name args _ constr derive) -> Just (DataInfo cxt name args [constr] derive)
    TyConI (DataD cxt name args _ constrs derive) -> Just (DataInfo cxt name args constrs derive)
    _ -> Nothing

-- | Convert the reified information of the datatype to a definition.
infoToDataD :: DataInfo () -> Dec
infoToDataD (DataInfo cxt name args cons deriv) = DataD cxt name args Nothing cons deriv

{- |
This function provides the name and the arity of the given data
constructor, and if it is a GADT also its type.
-}
normalCon :: Con -> (Name, [StrictType], Maybe Type)
normalCon (NormalC constr args) = (constr, args, Nothing)
normalCon (RecC constr args) = (constr, map (\(_, s, t) -> (s, t)) args, Nothing)
normalCon (InfixC a constr b) = (constr, [a, b], Nothing)
normalCon (ForallC _ _ constr) = normalCon constr
normalCon (GadtC (constr : _) args typ) = (constr, args, Just typ)
normalCon _ = error "missing case for 'normalCon'"

normalConExp :: Con -> Q (Name, [Type], Maybe Type)
normalConExp con = pure (n, map snd ts, t)
  where
    (n, ts, t) = normalCon con

containsType' :: Type -> Type -> [Int]
containsType' = run 0
  where
    run n s t
        | s == t = [n]
        | otherwise = case s of
            ForallT _ _ s' -> run n s' t
            -- only going through the right-hand side counts!
            AppT s1 s2 -> run n s1 t ++ run (n + 1) s2 t
            SigT s' _ -> run n s' t
            _ -> []

{- |
Auxiliary function to extract the first argument of a binary type
application (the second argument of this function). If the second
argument is @Nothing@ or not of the right shape, the first argument
is returned as a default.
-}
getBinaryFArg :: Type -> Maybe Type -> Type
getBinaryFArg _ (Just (AppT (AppT _ t) _)) = t
getBinaryFArg def _ = def

mkInstanceD :: Cxt -> Type -> [Dec] -> Dec
mkInstanceD = InstanceD Nothing

{- |
This function provides a list (of the given length) of new names based
on the given string.
-}
newNames :: Int -> String -> Q [Name]
newNames n name = replicateM n (newName name)

iter :: (Eq t, Num t, Quote m) => t -> m Exp -> m Exp -> m Exp
iter 0 _ e = e
iter n f e = iter (n - 1) f (f `appE` e)

-- | pures the name of a type variable.
tyVarName :: TyVarBndr a -> Name
tyVarName (PlainTV n _) = n
tyVarName (KindedTV n _ _) = n
