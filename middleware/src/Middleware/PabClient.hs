{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TypeApplications  #-}

module Middleware.PabClient where

import Colog.Polysemy.Effect          (Log)
import Colog.Polysemy.Formatting      (WithLog, logError)
import Data.Aeson                     (FromJSON, ToJSON)
import Data.Aeson.Types               (Value, toJSON)
import Data.Either.Combinators        (mapLeft)
import Dex.Types                      (Request (Request), historyId)
import Formatting
import GHC.Stack                      (HasCallStack)
import Middleware.Capability.Error
import Middleware.Capability.ReqIdGen (ReqIdGen, nextReqId)
import Middleware.Capability.Retry    (retryRequest)
import Middleware.Capability.Time     (Time)
import Middleware.PabClient.API       (API)
import Middleware.PabClient.Types
import Polysemy                       (Embed, Members, Sem, interpret, makeSem)
import Servant                        (Proxy (..), type (:<|>) ((:<|>)))
import Servant.Client.Streaming       (ClientM, client)
import Servant.Polysemy.Client        (ClientError, ServantClient, runClient, runClient')

data ManagePabClient r a where
  Status :: ContractInstanceId -> ManagePabClient r ContractState
  GetFunds :: ContractInstanceId -> ManagePabClient r [Fund]

makeSem ''ManagePabClient

data PabClient = PabClient
  { healthcheck    :: ClientM ()
  -- ^ call healthcheck method
  , instanceClient :: ContractInstanceId -> InstanceClient
  -- ^ call methods for instance client.
  }

-- | Contract instance endpoints
data InstanceClient = InstanceClient
  { getInstanceStatus    :: ClientM ContractState
  -- ^ get instance status
  , callInstanceEndpoint :: String -> Value -> ClientM ()
  -- ^ call instance endpoint
  , stopInstance         :: ClientM ()
  -- ^ call stop instance method
  }

-- | Init pab client
pabClient :: PabClient
pabClient = PabClient{..}
  where
    (healthcheck
      :<|> toInstanceClient
      ) = client (Proxy @API)

    instanceClient cid = InstanceClient{..}
        where
          (getInstanceStatus
            :<|> callInstanceEndpoint
            :<|> stopInstance
            ) = toInstanceClient cid


runPabClient :: (WithLog r, Members '[ServantClient, ReqIdGen, Error AppError, Time] r)
             => Sem (ManagePabClient ': r) a
             -> Sem r a
runPabClient =
  interpret
    (\case
        Status cid -> do
          let PabClient{instanceClient} = pabClient
              getStatus = getInstanceStatus . instanceClient $ cid
          callRes <- runClient' getStatus
          mapAppError callRes

        GetFunds cid ->
          callEndpoint cid "funds" ()

    )

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
   let PabClient{instanceClient} = pabClient
       callEndpoint' = callInstanceEndpoint . instanceClient $ cid
       getStatus = getInstanceStatus . instanceClient $ cid
   req <- wrapRequest a

   let body = toJSON req
       hid  = historyId req

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
