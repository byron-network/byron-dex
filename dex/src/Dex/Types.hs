{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE DuplicateRecordFields      #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# OPTIONS_GHC -Wno-redundant-constraints #-}
{-# OPTIONS_GHC -fno-specialise #-}
{-# OPTIONS_GHC -fno-strictness #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Dex.Types
  where

import           Data.Aeson          (FromJSON (parseJSON), ToJSON)

import           Data.Text           (Text)
import           Data.Word           (Word64)
import           Dex.WalletHistory
import           Ledger              (AssetClass, PubKeyHash, TxOutRef, ownHash)
import           Playground.Contract (Generic, ToSchema)
import qualified PlutusTx
import           PlutusTx.Prelude    (AdditiveGroup, AdditiveMonoid,
                                      AdditiveSemigroup, BuiltinByteString,
                                      BuiltinString, Eq, Integer,
                                      MultiplicativeMonoid,
                                      MultiplicativeSemigroup, return, ($),
                                      (&&), (<), (==))
import           Prelude             (Show)
import qualified Prelude
newtype Nat
  = Nat Integer
  deriving stock (Generic)
  deriving newtype
    ( AdditiveGroup
    , AdditiveMonoid
    , AdditiveSemigroup
    , MultiplicativeMonoid
    , MultiplicativeSemigroup
    , Prelude.Enum
    , Prelude.Eq
    , Prelude.Integral
    , Prelude.Num
    , Prelude.Ord
    , Prelude.Real
    , Show
    , ToJSON
    , ToSchema
    , Eq
    )

fromNat :: Nat -> Integer
fromNat (Nat x) = x

PlutusTx.makeIsDataIndexed ''Nat [('Nat,0)]
PlutusTx.makeLift ''Nat


instance FromJSON Nat where
  parseJSON value = do
    integer <- parseJSON @Integer value
    if integer < 0 then
        Prelude.fail "parsing Natural failed, unexpected negative number "
    else
        return $ Nat integer


data DexAction
  = Swap
  | CancelOrder
  | CollectCoins
  deriving (Show)

PlutusTx.makeIsDataIndexed
  ''DexAction
  [ ('Swap, 0)
  , ('CancelOrder, 1)
  , ('CollectCoins, 2)
  ]
PlutusTx.makeLift ''DexAction


data SellOrderParams
  = SellOrderParams
      { lockedCoin     :: AssetClass
      , expectedCoin   :: AssetClass
      , lockedAmount   :: Nat
      , expectedAmount :: Nat
      }
  deriving (FromJSON, Generic, Show, ToJSON)

PlutusTx.makeIsDataIndexed ''SellOrderParams [('SellOrderParams,0)]
PlutusTx.makeLift ''SellOrderParams

data LiquidityOrderParams
  = LiquidityOrderParams
      { lockedCoin     :: AssetClass
      , expectedCoin   :: AssetClass
      , lockedAmount   :: Nat
      , expectedAmount :: Nat
      }
  deriving (FromJSON, Generic, Show, ToJSON)

PlutusTx.makeIsDataIndexed ''LiquidityOrderParams [('LiquidityOrderParams,0)]
PlutusTx.makeLift ''LiquidityOrderParams



data SellOrderInfo
  = SellOrderInfo
      { lockedCoin     :: AssetClass
      , expectedCoin   :: AssetClass
      , expectedAmount :: Nat
      , ownerHash      :: PubKeyHash
      , orderId        :: BuiltinByteString
      }
  deriving (FromJSON, Generic, Show, ToJSON)
PlutusTx.makeIsDataIndexed ''SellOrderInfo [('SellOrderInfo,0)]
PlutusTx.makeLift ''SellOrderInfo

newtype CancelOrderParams
  = CancelOrderParams { orderHash :: TxOutRef }
  deriving (FromJSON, Generic, Show, ToJSON)
PlutusTx.makeIsDataIndexed ''CancelOrderParams [('CancelOrderParams, 0)]
PlutusTx.makeLift ''CancelOrderParams

data PayoutInfo
  = PayoutInfo
      { ownerHash :: PubKeyHash
      , orderId   :: BuiltinByteString
      }
  deriving (FromJSON, Generic, Show, ToJSON)
PlutusTx.makeIsDataIndexed ''PayoutInfo [('PayoutInfo,0)]
PlutusTx.makeLift ''PayoutInfo

data LiquidityOrderInfo
  = LiquidityOrderInfo
      { lockedCoin     :: AssetClass
      , expectedCoin   :: AssetClass
      , expectedAmount :: Nat
      , swapFee        :: (Nat, Nat)
      , ownerHash      :: PubKeyHash
      , orderId        :: BuiltinByteString
      }
  deriving (FromJSON, Generic, Show, ToJSON)

instance Eq LiquidityOrderInfo where
  {-# INLINEABLE (==) #-}
  (LiquidityOrderInfo lC eC eA sF oH oId) == (LiquidityOrderInfo lC' eC' eA' sF' oH' oId') =
    lC == lC' && eC == eC' && eA == eA' && sF == sF' && oH == oH' && oId == oId'


{-# INLINEABLE reversedLiquidityOrder #-}
reversedLiquidityOrder :: Integer -> LiquidityOrderInfo -> LiquidityOrderInfo
reversedLiquidityOrder liquidity LiquidityOrderInfo {..} =
  LiquidityOrderInfo
  { lockedCoin = expectedCoin
  , expectedCoin = lockedCoin
  , expectedAmount = Nat liquidity
  , swapFee = swapFee
  , ownerHash = ownerHash
  , orderId = orderId
  }

PlutusTx.makeIsDataIndexed ''LiquidityOrderInfo [('LiquidityOrderInfo,0)]
PlutusTx.makeLift ''LiquidityOrderInfo


data Order
  = SellOrder SellOrderInfo
  | LiquidityOrder LiquidityOrderInfo
  deriving (Generic, Show, FromJSON, ToJSON)

PlutusTx.makeIsDataIndexed
 ''Order
 [ ('SellOrder, 0)
 , ('LiquidityOrder, 1)
 ]
PlutusTx.makeLift ''Order

data DexDatum
  = Order Order
  | Payout PayoutInfo
  deriving (Generic, Show, FromJSON, ToJSON)


PlutusTx.makeIsDataIndexed
  ''DexDatum
  [ ('Order, 0)
  , ('Payout, 1)
  ]
PlutusTx.makeLift ''DexDatum


data Request a
  = Request
      { historyId  :: HistoryId
      , randomSeed :: Word64
      , content    :: a
      }
  deriving (FromJSON, Generic, Show, ToJSON)


data OrderInfo
  = OrderInfo
      { orderHash      :: TxOutRef
      , lockedCoin     :: AssetClass
      , expectedCoin   :: AssetClass
      , expectedAmount :: Nat
      , lockedAmount   :: Nat
      , ownerHash      :: PubKeyHash
      , orderType      :: Text
      }
  deriving (FromJSON, Generic, Show, ToJSON)


data DexContractState
  = Orders [(SellOrderInfo, TxOutRef)]
  | Sold
  | Performed
  | Stopped
  | Funds [(AssetClass, Integer)]
  | MyOrders [OrderInfo]
  | Cancel
  deriving (FromJSON, Generic, Show, ToJSON)
