{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TypeApplications  #-}

module Middleware.PabClient where

import           Colog.Polysemy.Effect          (Log)
import           Colog.Polysemy.Formatting      (WithLog, logDebug, logError)
import           Data.Aeson                     (FromJSON, ToJSON)
import           Data.Aeson.Types               (Value, toJSON)
import           Data.Either.Combinators        (mapLeft)
import           Dex.Types                      (AssetSet (AssetSet),
                                                 OrderInfo (OrderInfo),
                                                 PayoutSummary,
                                                 Request (Request), historyId)
import           Formatting
import           GHC.Stack                      (HasCallStack)
import           Middleware.Capability.Error
import           Middleware.Capability.ReqIdGen (ReqIdGen, nextReqId)
import           Middleware.Capability.Retry    (retryRequest)
import           Middleware.Capability.Time     (Time)
import           Middleware.Dex.Types           (CoinSet (CoinSet),
                                                 CreateCancelOrderParams,
                                                 CreateLiquidityOrderParams (CreateLiquidityOrderParams),
                                                 CreateLiquidityPoolParams (CreateLiquidityPoolParams),
                                                 CreateSellOrderParams,
                                                 PerformRandomParams (PerformRandomParams),
                                                 WalletId (WalletId),
                                                 convertCancelOrderToPab,
                                                 convertCoinSetToPab,
                                                 convertLiquidityOrderToPab,
                                                 convertLiquidityPoolToPab,
                                                 convertSellOrderToPab)
import           Middleware.PabClient.API       (API)
import           Middleware.PabClient.Types
import           Polysemy                       (Embed, Members, Sem, interpret,
                                                 makeSem)
import           Servant                        (Proxy (..),
                                                 type (:<|>) ((:<|>)))
import           Servant.Client.Streaming       (ClientM, client)
import           Servant.Polysemy.Client        (ClientError, ServantClient,
                                                 runClient, runClient')

data ManagePabClient r a where
  ActivateWallet            :: ContractActivationArgs -> ManagePabClient r ContractInstanceId
  Status                    :: ContractInstanceId -> ManagePabClient r ContractState
  GetFunds                  :: ContractInstanceId -> ManagePabClient r [Fund]
  CollectFunds              :: ContractInstanceId -> ManagePabClient r ()
  CreateSellOrder           :: ContractInstanceId -> CreateSellOrderParams -> ManagePabClient r ()
  CreateLiquidityPoolInPab  :: ContractInstanceId -> CreateLiquidityPoolParams -> ManagePabClient r ()
  CreateLiquidityOrderInPab :: ContractInstanceId -> CreateLiquidityOrderParams -> ManagePabClient r ()
  GetMyOrders               :: ContractInstanceId -> ManagePabClient r [OrderInfo]
  GetAllOrders              :: ContractInstanceId -> ManagePabClient r [OrderInfo]
  GetOrdersBySet            :: ContractInstanceId -> CoinSet -> ManagePabClient r [OrderInfo]
  GetSets                   :: ContractInstanceId -> ManagePabClient r [AssetSet]
  GetMyPayouts              :: ContractInstanceId -> ManagePabClient r PayoutSummary
  PerformInPab              :: ContractInstanceId -> ManagePabClient r ()
  PerformNRandomInPab       :: ContractInstanceId -> PerformRandomParams -> ManagePabClient r ()
  Stop                      :: ContractInstanceId -> ManagePabClient r ()
  CancelOrder               :: ContractInstanceId -> CreateCancelOrderParams -> ManagePabClient r ()

makeSem ''ManagePabClient

data PabClient = PabClient
  { -- | call healthcheck method
    healthcheck    :: ClientM (),
    -- | call activate method
    activate       :: ContractActivationArgs -> ClientM ContractInstanceId,
    -- | call methods for instance client.
    instanceClient :: ContractInstanceId -> InstanceClient
  }

-- | Contract instance endpoints
data InstanceClient = InstanceClient
  { -- | get instance status
    getInstanceStatus    :: ClientM ContractState,
    -- | call instance endpoint
    callInstanceEndpoint :: String -> Value -> ClientM (),
    -- | call stop instance method
    stopInstance         :: ClientM ()
  }

-- | Init pab client
pabClient :: PabClient
pabClient = PabClient {..}
  where
    ( healthcheck
        :<|> activate
        :<|> toInstanceClient
      ) = client (Proxy @API)

    instanceClient cid = InstanceClient {..}
      where
        ( getInstanceStatus
            :<|> callInstanceEndpoint
            :<|> stopInstance
          ) = toInstanceClient cid

runPabClient :: (WithLog r, Members '[ServantClient, ReqIdGen, Error AppError, Time] r)
             => Sem (ManagePabClient ': r) a
             -> Sem r a
runPabClient =
  interpret $
    \case
      ActivateWallet args -> do
          let PabClient{activate} = pabClient
              activateReq = activate args
          callRes <- runClient' activateReq
          mapAppError callRes

      Status cid -> do
          let PabClient{instanceClient} = pabClient
              getStatus = getInstanceStatus . instanceClient $ cid
          callRes <- runClient' getStatus
          mapAppError callRes

      GetFunds cid ->
          callEndpoint cid "funds" ()

      CreateSellOrder cid params ->
          callEndpoint cid "createSellOrder" (convertSellOrderToPab params)

      CreateLiquidityPoolInPab cid params ->
        callEndpoint cid "createLiquidityPool" (convertLiquidityPoolToPab params)

      CreateLiquidityOrderInPab cid params ->
        callEndpoint cid "createLiquidityOrder" (convertLiquidityOrderToPab params)

      GetMyOrders cid ->
          callEndpoint cid "myOrders" ()

      GetAllOrders cid ->
          callEndpoint cid "allOrders" ()

      GetOrdersBySet cid params ->
        callEndpoint cid "ordersBySet" (convertCoinSetToPab params)

      GetSets cid ->
        callEndpoint cid "sets" ()

      CancelOrder cid params ->
          callEndpoint cid "cancel" (convertCancelOrderToPab params)

      PerformInPab cid ->
          callEndpoint cid "perform" ()

      PerformNRandomInPab cid (PerformRandomParams n) ->
          callEndpoint cid "performNRandom" n

      CollectFunds cid ->
          callEndpoint cid "collectFunds" ()

      Stop cid ->
          callEndpoint cid "stop" ()

      GetMyPayouts cid ->
          callEndpoint cid "myPayouts" ()

    where
      mapAppError :: (WithLog r, Members '[Error AppError] r) => Either ClientError a -> Sem r a
      mapAppError (Left err) = do
        logError (text % shown) "Cannot fetch status from PAB, cause: " err
        throw $ HttpError err
      mapAppError (Right v) = pure v

callEndpoint :: forall r req res. (ToJSON req, FromJSON res, WithLog r, Members '[ServantClient, ReqIdGen, Error AppError, Time] r)
             => ContractInstanceId
             -> String
             -> req
             -> Sem r res
callEndpoint cid name a = do
  let PabClient {instanceClient} = pabClient
      callEndpoint' = callInstanceEndpoint . instanceClient $ cid
      getStatus = getInstanceStatus . instanceClient $ cid
  req <- wrapRequest a

  let body = toJSON req
      hid = historyId req

  -- send request, Retry three times with one second interval between.
  retryRequest 3 1 Right $ callEndpoint' name body

  -- receive response, Retry five times with two second interval between.
  retryRequest 5 2 (lookupResBody @res hid) getStatus

wrapRequest :: (ToJSON a, Members '[ReqIdGen] r) => a -> Sem r (Request a)
wrapRequest content = do
  id <- nextReqId
  let randomSeed = 3 -- make random later
      req = Request id randomSeed content
  pure req
