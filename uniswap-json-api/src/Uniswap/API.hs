module Uniswap.API
  where

import Control.Monad.Freer          (Eff, LastMember, Members)
import Data.Text                    (Text)
import Servant.Server               (Handler, HasServer (ServerT))
import Uniswap.Common.AppError      (AppError)
import Uniswap.Common.Logger        (Logger)
import Uniswap.Common.NextId        (NextId)
import Uniswap.Common.ServantClient (ServantClient)
import Uniswap.Common.Utils         (Time)
import Uniswap.LiquidityPool.API    (LiquidityPoolAPI, liquidityPoolAPI)
import Uniswap.PAB                  (UniswapPab)
import Uniswap.Types                (AppContext (..))


type API =
  LiquidityPoolAPI

api
  :: (LastMember Handler effs, Members
  '[ UniswapPab
   , ServantClient
   , NextId
   , Logger
   , AppError
   , Time
   , Handler
   ] effs)
  => ServerT API (Eff effs)
api = liquidityPoolAPI

