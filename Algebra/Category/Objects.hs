{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Algebra.Category.Objects where

import Algebra.Classes
import Algebra.Types
import Prelude (Int, Ord (..),otherwise,($))
import Data.Kind
import Data.Constraint
import Test.QuickCheck
import Test.QuickCheck.Property
import Control.Applicative

type TimesCon con = forall a b. (con a, con b) => con (a⊗b) :: Constraint
type PlusCon con = forall a b. (con a, con b) => con (a⊕b) :: Constraint
-- type LConTensor con = forall a b. con (a⊗b) => con a :: Constraint
-- type RConTensor con = forall a b. con (a⊗b) => con a :: Constraint

reprCon :: forall con x. (TimesCon con, PlusCon con, con One, con Zero) => Repr x -> Dict (con x)
reprCon = \case
  RPlus a b -> Dict \\ reprCon @con a \\ reprCon @con b
  RTimes a b -> Dict \\ reprCon @con a \\ reprCon @con b
  RZero -> Dict
  ROne -> Dict


type ProdObj :: forall {k}. (k -> Constraint) -> Constraint
class ProdObj (con :: k -> Constraint) where -- TensorClosed constraint causes problems in the Free module. (probabjy GHC bug)
  objprod :: (con a, con b) => Dict (con (a⊗b))
  objfstsnd :: forall z a b. (z ~ (a⊗b), con z) => Dict (con a, con b)
  objone :: Dict (con One)


type SumObj :: forall {k}. (k -> Constraint) -> Constraint
class SumObj (con :: k -> Constraint) where -- TensorClosed constraint causes problems in the Free module. (probabjy GHC bug)
  objsum :: (con a, con b) => Dict (con (a⊕b))
  objleftright :: forall z a b. (z ~ (a⊕b), con z) => Dict (con a, con b)
  objzero :: Dict (con Zero)


objSumProxy :: (SumObj con, con a, con b) => proxy1 a -> proxy2 b -> Dict (con (a⊕b))
objSumProxy _ _  = objsum

objProdProxy :: (ProdObj con, con a, con b) => proxy1 a -> proxy2 b -> Dict (con (a⊗b))
objProdProxy _ _  = objprod

type Trivial :: k -> Constraint
class Trivial x
instance Trivial x

instance ProdObj Trivial where
  objprod = Dict
  objfstsnd = Dict
  objone = Dict

instance SumObj Trivial where
  objsum = Dict
  objleftright = Dict
  objzero = Dict

instance ProdObj Finite where
  objprod = Dict
  objfstsnd = finiteFstsnd
  objone = Dict

instance SumObj Finite where
  objsum = Dict
  objleftright = finiteLeftRight
  objzero = Dict


data Some1  f where
  Some1 :: f x -> Some1 f

sizedArbRepr :: Int -> Gen (Some1 Repr)
sizedArbRepr n
  | n <= 1 = frequency [(1,pure(Some1 RZero)), (3,pure(Some1 ROne))]
  | otherwise = do
      Some1 l <- sizedArbRepr  (n `div` 2)
      Some1 r <- sizedArbRepr  (n `div` 2)
      elements [Some1 (RPlus l r),Some1 (RTimes l r)]


isArbitrary1 :: Repr x -> Dict (Arbitrary1 x)
isArbitrary1 = reprCon

isCoArbitrary :: Repr x -> Dict (CoArbitrary x)
isCoArbitrary = reprCon

instance Arbitrary (Some1 Repr) where
  arbitrary = sized sizedArbRepr

forallType :: (forall (x :: k). Repr x -> Property) -> Property
forallType gen = MkProperty $ do
  Some1 t <- (arbitrary :: Gen (Some1 Repr))
  unProperty (property (gen t))

arbitrary2' :: forall f x y. Arbitrary (f x y) => Repr x -> Repr y -> Gen (f x y)
arbitrary2' _ _ = arbitrary
