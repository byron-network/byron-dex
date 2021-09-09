module Uniswap.Api.Endpoint where

import Prelude hiding ((/))
import Data.Generic.Rep (class Generic)
import Routing.Duplex (RouteDuplex', prefix, root)
import Routing.Duplex.Generic (noArgs, sum)
import Routing.Duplex.Generic.Syntax ((/))
import Uniswap.Data.Wallet (Wallet)

data Endpoint
  = Pools
  | Funds
  | CreatePool
  | ClosePool
  | AddToPool
  | RemoveFromPool
  | Swap
  | SwapPreview
  | IndirectSwap
  | IndirectSwapPreview

derive instance genericEndpoint :: Generic Endpoint _

endpointCodec :: Wallet -> RouteDuplex' Endpoint
endpointCodec wallet =
  root $ prefix wallet.instance
    $ sum
        { "Pools": "pools" / noArgs
        , "Funds": "funds" / noArgs
        , "CreatePool": "create" / noArgs
        , "ClosePool": "close" / noArgs
        , "AddToPool": "add" / noArgs
        , "RemoveFromPool": "remove" / noArgs
        , "Swap": "swap" / noArgs
        , "SwapPreview": "swap-preview" / noArgs
        , "IndirectSwap": "indirect-swap" / noArgs
        , "IndirectSwapPreview": "indirect-swap-preview" / noArgs
        }
