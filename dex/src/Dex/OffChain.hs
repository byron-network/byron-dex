{-# LANGUAGE AllowAmbiguousTypes        #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE DuplicateRecordFields      #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}

{-# LANGUAGE NamedFieldPuns             #-}
module Dex.OffChain
  where

import           Control.Lens.Getter     (view)
import           Control.Monad           hiding (fmap, mapM, mapM_)
import           Data.List               (foldl')
import qualified Data.Map                as Map
import           Data.Proxy              (Proxy (..))
import           Data.Text               (Text)
import           Data.UUID               as UUID
import           Data.Void               (Void)
import           Dex.OnChain             (mkDexValidator)
import           Dex.Types
import           Dex.WalletHistory       as WH
import qualified GHC.Classes
import           GHC.TypeLits            (symbolVal)
import           Ledger                  hiding (fee, singleton)
import           Ledger.Constraints      as Constraints
import qualified Ledger.Typed.Scripts    as Scripts
import           Ledger.Value            (AssetClass (..), assetClassValue,
                                          assetClassValueOf, getValue)
import           Playground.Contract
import           Plutus.Contract
import qualified PlutusTx
import qualified PlutusTx.AssocMap       as AssocMap
import           PlutusTx.Builtins.Class (stringToBuiltinByteString)
import           PlutusTx.Prelude        hiding (Semigroup (..), unless)
import           Prelude                 (Double, Semigroup (..), ceiling,
                                          fromIntegral, (/))
import qualified Prelude
import           System.Random
import           System.Random.SplitMix
data Dex


type DexState = History (Either Text DexContractState)

instance Scripts.ValidatorTypes Dex where
  type RedeemerType Dex = DexAction
  type DatumType Dex = DexDatum


dexInstance :: Scripts.TypedValidator Dex
dexInstance =
  Scripts.mkTypedValidator @Dex
    $$(PlutusTx.compile [||mkDexValidator||])
    $$(PlutusTx.compile [||wrap||])
  where
    wrap = Scripts.wrapValidator @DexDatum @DexAction


type DexSchema =
  Endpoint "createSellOrder" (Request SellOrderParams)
  .\/ Endpoint "createLiquidityOrder" (Request LiquidityOrderParams)
  .\/ Endpoint "perform" (Request ())
  .\/ Endpoint "stop" (Request ())
  .\/ Endpoint "funds" (Request ())
  .\/ Endpoint "findOrders" (Request ())
  .\/ Endpoint "orders" (Request ())
  .\/ Endpoint "cancel" (Request CancelOrderParams)



getConstraintsForSwap :: ChainIndexTxOut -> TxOutRef  -> Order -> TxConstraints DexAction DexDatum
getConstraintsForSwap _ txOutRef (SellOrder SellOrderInfo {..}) =
  Constraints.mustPayToTheScript
    (Payout PayoutInfo {..})
    (singleton expectedCoin expectedAmount)
  <> Constraints.mustSpendScriptOutput txOutRef (Redeemer $ PlutusTx.toBuiltinData Swap)

getConstraintsForSwap txOut txOutRef (LiquidityOrder lo@LiquidityOrderInfo {..}) =
  let (numerator, denominator) = swapFee
      fee = fromIntegral expectedAmount Prelude.* fromIntegral numerator Prelude./ fromIntegral denominator
      integerFee = ceiling @Double @Integer fee
  in Constraints.mustPayToTheScript
    (Payout PayoutInfo {..})
    (assetClassValue expectedCoin integerFee)
  <> Constraints.mustPayToTheScript
    (Order (LiquidityOrder (reversedLiquidityOrder (assetClassValueOf (view ciTxOutValue txOut) lockedCoin) lo)))
    (singleton expectedCoin expectedAmount)
  <> Constraints.mustSpendScriptOutput txOutRef (Redeemer $ PlutusTx.toBuiltinData Swap)

uuidToBBS :: UUID.UUID -> BuiltinByteString
uuidToBBS = stringToBuiltinByteString . UUID.toString

createSellOrder :: SMGen -> SellOrderParams -> Contract DexState DexSchema Text UUID
createSellOrder smgen SellOrderParams {..} = do
  ownerHash <- pubKeyHash <$> ownPubKey
  let uuid = head $ randoms @UUID.UUID smgen
  let orderInfo = SellOrderInfo
                    { expectedCoin = expectedCoin
                    , lockedCoin = lockedCoin
                    , expectedAmount = expectedAmount
                    , ownerHash = ownerHash
                    , orderId = uuidToBBS uuid
                    }
  let tx = Constraints.mustPayToTheScript (Order $ SellOrder orderInfo) (singleton lockedCoin lockedAmount)
  void $ submitTxConstraints dexInstance tx
  return uuid


createLiquidityOrder :: SMGen -> LiquidityOrderParams -> Contract DexState DexSchema Text UUID
createLiquidityOrder smgen LiquidityOrderParams {..} = do
  ownerHash <- pubKeyHash <$> ownPubKey
  let uuid = head $ randoms @UUID.UUID smgen
  let orderInfo =
        LiquidityOrderInfo
          { expectedCoin = expectedCoin
          , lockedCoin = lockedCoin
          , expectedAmount = expectedAmount
          , swapFee = swapFee
          , ownerHash = ownerHash
          , orderId = uuidToBBS uuid
          }
  let tx = Constraints.mustPayToTheScript (Order $ LiquidityOrder orderInfo) (singleton lockedCoin lockedAmount)
  void $ submitTxConstraints dexInstance tx
  return uuid


perform :: Contract DexState DexSchema Text ()
perform = do
  pkh <- pubKeyHash <$> ownPubKey
  let address = Ledger.scriptAddress $ Scripts.validatorScript dexInstance
  utxos <- Map.toList <$> utxosAt address
  mapped <- mapM (\(oref, txOut) -> getDexDatum txOut >>= \d -> return (txOut, oref, d)) utxos
  let filtered = [(txOut, oref, o) | (txOut, oref, Order o) <- mapped]
  let lookups = Constraints.typedValidatorLookups dexInstance
          <> Constraints.ownPubKeyHash pkh
          <> Constraints.otherScript (Scripts.validatorScript dexInstance)
          <> Constraints.unspentOutputs (Map.fromList utxos)
      tx = foldl' (\acc (o, oref, order) -> acc <> getConstraintsForSwap o oref order
        ) mempty filtered
  void $ submitTxConstraintsWith lookups tx


funds :: Contract w s Text [(AssetClass, Integer)]
funds = do
  pkh <- pubKeyHash <$> ownPubKey
  os <- Map.elems <$> utxosAt (pubKeyHashAddress pkh)
  let walletValue = getValue $ mconcat [view ciTxOutValue o | o <- os]
  return [(AssetClass (cs, tn),  a) | (cs, tns) <- AssocMap.toList walletValue, (tn, a) <- AssocMap.toList tns]


orders :: Contract DexState DexSchema Text [OrderInfo]
orders = do
  pkh <- pubKeyHash <$> ownPubKey
  let address = Ledger.scriptAddress $ Scripts.validatorScript dexInstance
  utxos <- Map.toList <$> utxosAt address
  mapped <- mapM toOrderInfo utxos
  return $ filter (\OrderInfo {..} -> ownerHash == pkh) mapped
  where
    toOrderInfo (orderHash, o) = do
      order <- getOrderDatum o
      case order of
        LiquidityOrder LiquidityOrderInfo {..} ->
          let orderType = "Liquidity"
              lockedAmount = Nat (assetClassValueOf (view ciTxOutValue o) lockedCoin)
          in return OrderInfo {..}
        SellOrder      SellOrderInfo      {..} ->
          let orderType = "Sell"
              lockedAmount = Nat (assetClassValueOf (view ciTxOutValue o) lockedCoin)
          in return OrderInfo {..}

cancel :: CancelOrderParams -> Contract DexState DexSchema Text ()
cancel CancelOrderParams {..} = do
  pkh <- pubKeyHash <$> ownPubKey
  let address = Ledger.scriptAddress $ Scripts.validatorScript dexInstance
  utxos  <- Map.toList . Map.filterWithKey (\oref' _ -> oref' == orderHash) <$> utxosAt address
  hashes <- mapM (toOwnerHash . snd) utxos

  when (any (/= pkh) hashes || Prelude.null hashes) (throwError "Cannot find order by provided hash")

  let lookups =
        Constraints.typedValidatorLookups dexInstance
        <> Constraints.ownPubKeyHash pkh
        <> Constraints.otherScript (Scripts.validatorScript dexInstance)
        <> Constraints.unspentOutputs (Map.fromList utxos)

      tx     = Constraints.mustSpendScriptOutput orderHash $ Redeemer $ PlutusTx.toBuiltinData CancelOrder

  void $ submitTxConstraintsWith lookups tx

  where
    toOwnerHash :: ChainIndexTxOut -> Contract w s Text PubKeyHash
    toOwnerHash o = do
      order <- getOrderDatum o
      case order of
        SellOrder SellOrderInfo {..}           -> return ownerHash
        LiquidityOrder LiquidityOrderInfo {..} -> return ownerHash

getDexDatum :: ChainIndexTxOut -> Contract w s Text DexDatum
getDexDatum ScriptChainIndexTxOut { _ciTxOutDatum } = do
        (Datum e) <- either getDatum pure _ciTxOutDatum
        maybe (throwError "datum hash wrong type") pure (PlutusTx.fromBuiltinData e)
  where
    getDatum :: DatumHash -> Contract w s Text Datum
    getDatum =
      datumFromHash >=>
      \case Nothing -> throwError "datum not found"
            Just d  -> pure d
getDexDatum _ = throwError "no datum for a txout of a public key address"

getOrderDatum :: ChainIndexTxOut -> Contract w s Text Order
getOrderDatum ScriptChainIndexTxOut { _ciTxOutDatum } = do
        (Datum e) <- either getDatum pure _ciTxOutDatum
        o <- maybe (throwError "datum hash wrong type")
              pure
              (PlutusTx.fromBuiltinData e)
        case o of
          Order order -> return order
          _           -> throwError "datum hash wrong type"
  where
    getDatum :: DatumHash -> Contract w s Text Datum
    getDatum =
      datumFromHash >=>
      \case Nothing -> throwError "datum not found"
            Just d  -> pure d
getOrderDatum _ = throwError "no datum for a txout of a public key address"



dexEndpoints :: Contract DexState DexSchema Void ()
dexEndpoints =
  selectList [stop', createSellOrder', createLiquidityOrder', perform', orders', funds', cancel'] >> dexEndpoints
  where
    f ::
      forall l a p.
      (HasEndpoint l p DexSchema, FromJSON p) =>
      Proxy l ->
      (p -> Text) ->
      (a -> DexContractState) ->
      (p -> Contract DexState DexSchema Text a) ->
      Promise DexState DexSchema Void ()
    f _ getHistoryId g c = handleEndpoint @l $ \p -> do
      let hid = either (const "ERROR") getHistoryId p
      e <- either (pure . Left) (runError @_ @_ @Text . c) p

      case e of
        Left err -> do
          logInfo @Text ("Error during calling endpoint: " <> err)
          tell $ WH.append hid . Left $ err
        Right a
          | symbolVal (Proxy @l) GHC.Classes./= "clearState" ->
            tell $ WH.append hid . Right . g $ a
        _ -> return ()

    stop' :: Promise DexState DexSchema Void ()
    stop' = handleEndpoint @"stop" $ \e -> do
      tell $ case e of
        Left err                -> WH.append "ERROR" $ Left err
        Right (Request hId _ _) -> WH.append hId $ Right Stopped

    createLiquidityOrder' = f (Proxy @"createLiquidityOrder") historyId (const OrderCreated) (\Request {..} -> createLiquidityOrder (mkSMGen $ fromIntegral randomSeed) content)
    createSellOrder'    = f (Proxy @"createSellOrder") historyId (const OrderCreated) (\Request {..} -> createSellOrder (mkSMGen $ fromIntegral randomSeed) content)
    perform' = f (Proxy @"perform") historyId (const Performed) (const perform)
    orders'  = f (Proxy @"orders") historyId MyOrders (const orders)
    funds'   = f (Proxy @"funds") historyId Funds (const funds)
    cancel'  = f (Proxy @"cancel") historyId (const Cancel) (\Request {..} -> cancel content)