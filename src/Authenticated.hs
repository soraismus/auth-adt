{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DeriveFunctor #-}
module Authenticated (
  runProver,
  runVerifier,
  Auth(..),
  AuthM,
  auth,
  unAuth,
  Shallow(..),
) where
import Protolude hiding (Hashable)
import Control.Monad.State
import Control.Monad.Except
import GHC.Generics
import qualified Data.Sequence as Seq
import Data.Sequence (ViewL(..))
import Hash


-- | A sequence of shallow projections
type ProofStream s = (Seq s)

-- | Errors returned by runVerifier
data AuthError = NoMoreProofElems | MismatchedHash Hash Hash deriving (Show, Eq)

-- | An authenticated computation
type AuthM s a = ExceptT AuthError (State (ProofStream s)) a

-- | Either the value with the hash, or just the hash
data Auth a = WithHash a Hash | OnlyHash Hash deriving (Show, Eq, Functor)

instance Hashable a => Hashable (Auth a) where
  toHash (WithHash _ h) = h
  toHash (OnlyHash h) =h

-- | Tag a value with its hash
auth :: Hashable a => a -> Auth a
auth a = WithHash a (toHash a)

-- | When called as Prover, push a shallow version of the auth value to the proof stream
-- and when called as Verifier take a shallow from the proof stream and compare it to the
-- given elements hash
unAuth :: (Shallow a, Hashable a) => Auth a -> AuthM a a
unAuth (WithHash a h) = do
  modify (Seq.|> (shallow a))
  return a
unAuth (OnlyHash hash) = do
  stream <- get
  case Seq.viewl stream of
    EmptyL        -> throwError NoMoreProofElems
    shallow :< xs -> do
      put xs
      let shallowHash = toHash shallow
      if shallowHash == hash
        then return shallow
        else throwError $ MismatchedHash shallowHash hash

-- | Create a shallow projection
class Shallow f where
  shallow :: f -> f
  {-default shallow :: (Generic1 f, GShallow (Rep1 f)) => f a -> f a-}
  {-shallow = to1 . gshallow . from1-}

instance Shallow (Auth a) where
  shallow (WithHash a h ) = OnlyHash h
  shallow h = h

-- | From a computation, produce the result and the proof stream
runProver :: AuthM s a -> (Either AuthError a, ProofStream s)
runProver m = runState (runExceptT m) Seq.empty

-- | Verify a computation with a proof stream
runVerifier
  :: AuthM s a
  -> ProofStream s
  -> Either AuthError a
runVerifier m = evalState (runExceptT m)

{-class GShallow f where-}
  {-gshallow :: f a -> f a-}

{-instance GShallow U1 where-}
  {-gshallow U1 = U1-}

{-instance (Shallow f) => GShallow (Rec1 f) where-}
  {-gshallow (Rec1 f) = Rec1 (shallow f)-}

{-instance GShallow (K1 i c) where-}
  {-gshallow (K1 c) = (K1 c)-}

{-instance GShallow f => GShallow (M1 i t f) where-}
  {-gshallow (M1 a) = M1 (gshallow a)-}

{-instance (GShallow l, GShallow r) => GShallow (l :+: r) where-}
  {-gshallow (L1 a) = L1 (gshallow a)-}
  {-gshallow (R1 a) = R1 (gshallow a)-}

{-instance (GShallow l, GShallow r) => GShallow (l :*: r) where-}
  {-gshallow (a :*: b) = gshallow (a) :*: gshallow (b)-}

