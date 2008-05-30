{-# OPTIONS -fglasgow-exts -cpp #-}

{-| Some common syntactic entities are defined in this module.
-}
module Syntax.Common where

import Data.Generics (Typeable, Data)
import Control.Applicative
import Data.Foldable
import Data.Traversable

import Syntax.Position
import Utils.Monad
import Utils.Size

#include "../undefined.h"
import Utils.Impossible

data Hiding  = Hidden | NotHidden
    deriving (Typeable, Data, Show, Eq)

-- | A function argument can be hidden.
data Arg e  = Arg { argHiding :: Hiding, unArg :: e }
    deriving (Typeable, Data, Eq)

instance Functor Arg where
    fmap f (Arg h x) = Arg h $ f x

instance Foldable Arg where
    foldr f z (Arg _ x) = f x z

instance Traversable Arg where
    traverse f (Arg h x) = Arg h <$> f x

instance HasRange a => HasRange (Arg a) where
    getRange = getRange . unArg

instance Sized a => Sized (Arg a) where
  size = size . unArg

instance Show a => Show (Arg a) where
    show (Arg Hidden x)    = "{" ++ show x ++ "}"
    show (Arg NotHidden x) = "(" ++ show x ++ ")"

data Named name a =
    Named { nameOf     :: Maybe name
	  , namedThing :: a
	  }
    deriving (Eq, Typeable, Data)

unnamed :: a -> Named name a
unnamed = Named Nothing

named :: name -> a -> Named name a
named = Named . Just

instance Functor (Named name) where
    fmap f (Named n x) = Named n $ f x

instance Foldable (Named name) where
    foldr f z (Named _ x) = f x z

instance Traversable (Named name) where
    traverse f (Named n x) = Named n <$> f x

instance HasRange a => HasRange (Named name a) where
    getRange = getRange . namedThing

instance Sized a => Sized (Named name a) where
  size = size . namedThing

instance Show a => Show (Named String a) where
    show (Named Nothing x)  = show x
    show (Named (Just n) x) = n ++ " = " ++ show x

-- | Only 'Hidden' arguments can have names.
type NamedArg a = Arg (Named String a)

-- | Functions can be defined in both infix and prefix style. See
--   'Syntax.Concrete.LHS'.
data IsInfix = InfixDef | PrefixDef
    deriving (Typeable, Data, Show, Eq)

-- | Access modifier.
data Access = PrivateAccess | PublicAccess
    deriving (Typeable, Data, Show, Eq)

-- | Abstract or concrete
data IsAbstract = AbstractDef | ConcreteDef
    deriving (Typeable, Data, Show, Eq)

type Nat    = Integer
type Arity  = Nat

-- | The unique identifier of a name. Second argument is the top-level module
--   identifier.
data NameId = NameId Nat Integer
    deriving (Eq, Ord, Typeable, Data)

instance Enum NameId where
  succ (NameId n m)	= NameId (n + 1) m
  pred (NameId n m)	= NameId (n - 1) m
  toEnum n		= __IMPOSSIBLE__  -- should not be used
  fromEnum (NameId n _) = fromIntegral n

