{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}

{-# options_ghc -fno-warn-orphans          #-}
{-# options_ghc -Wno-redundant-constraints #-}
{-# options_ghc -fno-strictness            #-}
{-# options_ghc -fno-specialise            #-}

module Uniswap.Types
  where

import           Ledger
import           Ledger.Value        (AssetClass (..), assetClass,
                                      assetClassValue, assetClassValueOf)
import           Playground.Contract (FromJSON, Generic, ToJSON, ToSchema)
import qualified PlutusTx
import           PlutusTx.Prelude
import           Prelude             (Show)
import qualified Prelude
import           Text.Printf         (PrintfArg)

-- | Uniswap coin token
data U = U
PlutusTx.makeIsDataIndexed ''U [('U, 0)]
PlutusTx.makeLift ''U

-- | "A"-side coin token
data A = A
PlutusTx.makeIsDataIndexed ''A [('A, 0)]
PlutusTx.makeLift ''A

-- | "B"-side coin token
data B = B
PlutusTx.makeIsDataIndexed ''B [('B, 0)]
PlutusTx.makeLift ''B

-- | Pool-state coin token
data PoolState = PoolState
PlutusTx.makeIsDataIndexed ''PoolState [('PoolState, 0)]
PlutusTx.makeLift ''PoolState

-- | Liquidity-state coin token
data Liquidity = Liquidity
PlutusTx.makeIsDataIndexed ''Liquidity [('Liquidity, 0)]
PlutusTx.makeLift ''Liquidity

-- Note: An orphan instance here because of the newtype wrapper below.
deriving anyclass instance ToSchema AssetClass

-- | A single 'AssetClass'. Because we use three coins, we use a phantom type to track
-- which one is which.
newtype Coin a = Coin { unCoin :: AssetClass }
  deriving stock   (Show, Generic)
  deriving newtype (ToJSON, FromJSON, ToSchema, Eq, Prelude.Eq, Prelude.Ord)
PlutusTx.makeIsDataIndexed ''Coin [('Coin, 0)]
PlutusTx.makeLift ''Coin

-- | Likewise for 'Integer'; the corresponding amount we have of the
-- particular 'Coin'.
newtype Amount a = Amount { unAmount :: Integer }
  deriving stock   (Show, Generic)
  deriving newtype (ToJSON, FromJSON, ToSchema, Eq, Ord, PrintfArg)
  deriving newtype (Prelude.Eq, Prelude.Ord, Prelude.Num, Prelude.Enum, Prelude.Real, Prelude.Integral)
  deriving newtype (AdditiveGroup, AdditiveMonoid, AdditiveSemigroup, MultiplicativeSemigroup)
PlutusTx.makeIsDataIndexed ''Amount [('Amount, 0)]
PlutusTx.makeLift ''Amount

{-# INLINABLE valueOf #-}
valueOf :: Coin a -> Amount a -> Value
valueOf c a = assetClassValue (unCoin c) (unAmount a)

{-# INLINABLE unitValue #-}
unitValue :: Coin a -> Value
unitValue c = valueOf c 1

{-# INLINABLE isUnity #-}
isUnity :: Value -> Coin a -> Bool
isUnity v c = amountOf v c == 1

{-# INLINABLE amountOf #-}
amountOf :: Value -> Coin a -> Amount a
amountOf v = Amount . assetClassValueOf v . unCoin

{-# INLINABLE mkCoin #-}
mkCoin:: CurrencySymbol -> TokenName -> Coin a
mkCoin c = Coin . assetClass c

newtype Uniswap = Uniswap
    { usCoin :: Coin U
    } deriving stock    (Show, Generic)
      deriving anyclass (ToJSON, FromJSON, ToSchema)
      deriving newtype  (Prelude.Eq, Prelude.Ord)
PlutusTx.makeIsDataIndexed ''Uniswap [('Uniswap, 0)]
PlutusTx.makeLift ''Uniswap

data LiquidityPool = LiquidityPool
    { lpCoinA :: Coin A
    , lpCoinB :: Coin B
    }
    deriving (Show, Generic, ToJSON, FromJSON, ToSchema)


PlutusTx.makeIsDataIndexed ''LiquidityPool [('LiquidityPool, 0)]
PlutusTx.makeLift ''LiquidityPool


liquidityPool :: (Coin A, Coin B) -> LiquidityPool
liquidityPool (Coin a,Coin b) = LiquidityPool (Coin (min a b)) (Coin (max a b))



instance Eq LiquidityPool where
    {-# INLINABLE (==) #-}
    x == y = (lpCoinA x == lpCoinA y && lpCoinB x == lpCoinB y) ||
              -- Make sure the underlying coins aren't equal.
             (unCoin (lpCoinA x) == unCoin (lpCoinB y) && unCoin (lpCoinB x) == unCoin (lpCoinA y))


instance Prelude.Eq LiquidityPool where
    x == y = (lpCoinA x == lpCoinA y && lpCoinB x == lpCoinB y) ||
              -- Make sure the underlying coins aren't equal.
             (unCoin (lpCoinA x) == unCoin (lpCoinB y) && unCoin (lpCoinB x) == unCoin (lpCoinA y))


instance Prelude.Ord LiquidityPool where
  compare (LiquidityPool a b) (LiquidityPool a2 b2) =
    let (a',b') = if unCoin a <= unCoin b then (a,b) else (Coin $ unCoin b,Coin $ unCoin a)
        (a2',b2') = if unCoin a2 <= unCoin b2 then (a2,b2) else (Coin $ unCoin b2, Coin $ unCoin a2)
    in Prelude.compare (a',b') (a2',b2')

data UniswapAction = Create LiquidityPool | Close | Swap | ISwap | Remove | Add
    deriving Show
PlutusTx.makeIsDataIndexed ''UniswapAction [ ('Create , 0)
                                           , ('Close,   1)
                                           , ('Swap,    2)
                                           , ('ISwap,   3)
                                           , ('Remove,  4)
                                           , ('Add,     5)
                                           ]
PlutusTx.makeLift ''UniswapAction

data UniswapDatum =
      Factory [LiquidityPool]
    | Pool LiquidityPool (Amount Liquidity)
    deriving stock (Show)
PlutusTx.makeIsDataIndexed ''UniswapDatum [ ('Factory, 0)
                                          , ('Pool,    1)
                                          ]
PlutusTx.makeLift ''UniswapDatum
