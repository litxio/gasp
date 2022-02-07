{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Algebra.Morphism.Polynomial.Multi where

import Prelude ((&&), Bool(..), Int, Eq(..), Ord(..),Show(..), Functor(..), fromIntegral, id,(.),(||),Integer,Foldable(..),error)
import Data.List (intercalate,and)
import Data.Monoid
import Algebra.Classes
import Algebra.Morphism.Exponential
import qualified Algebra.Morphism.LinComb as LC
import Algebra.Morphism.LinComb (LinComb(..))
import qualified Data.Map as M
import Data.Maybe (Maybe (..))
import Data.Traversable
import Control.Applicative
import Data.Function

-- | Monomial over an element set e, mapping each element to its
-- exponent
newtype Monomial e = M (Exp (LinComb e Int)) deriving (Multiplicative,Division,Ord,Eq,Show)

monoLinComb :: Monomial e -> LinComb e Int
monoLinComb (M (Exp x)) = x
-- Note: derived ordering is lexicographic.

mapMonoVars :: Ord e => (t -> e) -> Monomial t -> Monomial e
mapMonoVars f (M (Exp m)) = M (Exp (LC.mapVars f m)) 

traverseMonoVars :: (Applicative f, Ord e) => (v -> f e) -> Monomial v -> f (Monomial e)
traverseMonoVars f (M (Exp x)) = M . Exp <$> (LC.traverseVars f x)

monoDegree :: Monomial e -> Int
monoDegree =  LC.eval id (\_ -> 1) . monoLinComb
  -- LC.eval id (\_ -> Scalar 1) m

-- >>> monoDegree (varM "x" ^+3 * varM "y" ^+2)
-- 5

monoDivisible :: Ord k => Monomial k -> Monomial k -> Bool
monoDivisible (M (Exp (LinComb m))) (M (Exp (LinComb n))) =
  M.isSubmapOfBy (<=) m n


monoLcm :: Ord v => Monomial v -> Monomial v -> Monomial v
monoLcm (M (Exp (LinComb a))) (M (Exp (LinComb b)))
  = M $ Exp $ LinComb $ M.unionWith max a b

-- monoComplement m n * m = monoLcm m n
monoComplement :: Ord v => Monomial v -> Monomial v -> Monomial v
monoComplement m n = monoLcm m n / m


mapVars  :: Ord e => (t -> e) -> Polynomial t c -> Polynomial e c
mapVars f = P . LC.mapVars (mapMonoVars f) . fromPoly

-- | Map each monomial to its coefficient
newtype Polynomial e c = P {fromPoly :: LC.LinComb (Monomial e) c}
  deriving (Additive,Group,AbelianAdditive,Functor,Foldable,Traversable,Eq,Ord,DecidableZero,Show)
deriving instance {-# Overlappable #-} Scalable s a => Scalable s (Polynomial k a)

instance (Ring c, DecidableZero c, Ord e) => Multiplicative (Polynomial e c) where
  one = P (LC.var one)
  P p * P q = P (LC.fromList [(m1 * m2, coef1 * coef2) | (m1,coef1) <- LC.toList p, (m2,coef2) <- LC.toList q])

isConstant :: (Eq c, Ord e, Additive c) => Polynomial e c -> Maybe c
isConstant (P p) = if and [m == one || c == zero | (m,c) <- LC.toList p] then
                     Just (M.findWithDefault zero one (fromLinComb p)) else Nothing

instance (DecidableZero c, Ring c, Ord e) => Scalable (Polynomial e c) (Polynomial e c) where
  (*^) = (*)

instance (DecidableZero c,Ring c,Ord e) => Ring (Polynomial e c) where
  fromInteger = constPoly . fromInteger

prodMonoPoly, (*!) :: (Ord e) => Monomial e -> Polynomial e c -> Polynomial e c
prodMonoPoly m (P p) = P (LC.mulVarsMonotonic m p)
(*!) = prodMonoPoly

-- This instance is incoherent, because there could be Scalable (Monomial e) c.
-- instance (Eq c, Ord c,Ring c, Ord e) => Scalable (Monomial e) (Polynomial e c) where
--   (*^) = prodMonoPoly

-------------------------------
-- Construction

varM :: e -> Monomial e
varM x = M (Exp (LC.var x))

-- >>> (varM "x" * varM "y" * varM "x" ^ 2)
-- M {fromM = Exp {fromExp = LinComb {fromLinComb = fromList [("x",3),("y",1)]}}}

varP :: Multiplicative c => e -> Polynomial e c
varP x = monoPoly (varM x)

-- >>> varP "x" + varP "y"
-- 1"x"+1"y"

-- >>> (varP "x" ^+ 2)
-- "x"^2

-- >>> ((varP "x" ^+ 2) * varP "y" + varP "y") * ((varP "x" ^+ 2) * varP "y" + varP "y")
-- 2"x"^2"y"^2+"x"^4"y"^2+"y"^2

monoPoly :: Multiplicative c => Monomial e -> Polynomial e c
monoPoly m = P (LC.var m)

constPoly :: DecidableZero c => Additive c => Ord e => c -> Polynomial e c
constPoly c = P (LC.fromList [(one,c)])


-------------------------------
-- Evaluation

evalMono ::  Multiplicative x => (e -> x) -> Monomial e -> x
evalMono f (M (Exp m)) = fromLog (LC.eval @Integer fromIntegral (Log . f) m)

eval' :: (Multiplicative x, Additive x, Scalable c x) => (e -> x) -> Polynomial e c -> x
eval' = eval id

eval :: (Multiplicative x, Additive x, Scalable d x) => (c -> d) -> (v -> x) -> Polynomial v c -> x
eval fc fe (P p) = LC.eval fc (evalMono fe) p

-------------------------------
-- Substitution by evaluation

type Substitution e f c = e -> Polynomial f c

substMono :: DecidableZero c => Ord f => Ring c => Substitution e f c -> Monomial e -> Polynomial f c
substMono = evalMono

subst :: DecidableZero c => Ord f => Ord e => Ring c => Substitution e f c -> Polynomial e c -> Polynomial f c
subst = eval'

----------------------------
-- Traversing

bitraverse :: Ord w => Applicative f => (v -> f w) -> (c -> f d) -> Polynomial v c -> f (Polynomial w d)
bitraverse f g (P x) = P <$> LC.bitraverse (traverseMonoVars f) g x

-------------------------
-- Gröbner basis, division

leadingView :: Polynomial v c -> Maybe ((Monomial v,c),Polynomial v c)
leadingView (P (LinComb a)) = flip fmap (M.minViewWithKey a) $ \
  (x,xs) -> (x, P (LinComb xs))


spoly :: Field c => DecidableZero c => Ord v => Polynomial v c -> Polynomial v c -> Polynomial v c
spoly f@(leadingView -> Just ((m,a),_)) g@(leadingView -> Just ((n,b),_))
  = (n' *! f) - (a/b) *^ (m' *! g) where
      n' = monoComplement m n
      m' = monoComplement n m
spoly _ _ = error "spoly: zero"

normalForm :: Eq c => DecidableZero c => Field c => Ord x => Polynomial x c -> [Polynomial x c] -> Polynomial x c 
normalForm f s = go f where
  go h | isZero h    = zero
       | []    <- s' = h
       | (g:_) <- s' = go (spoly h g)
       where
         s' = [g | g <- s, lm h `monoDivisible` lm g]
         lm x = case leadingView x of
           Nothing -> error "normalForm: zero"
           Just ((m,_),_) -> m

