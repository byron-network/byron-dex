module Uniswap.Component.Router where

import Prelude
import Data.Either (hush)
import Data.Maybe (Maybe(..), fromMaybe)
import Effect.Aff.Class (class MonadAff)
import Halogen (liftEffect)
import Halogen as H
import Halogen.HTML as HH
import Halogen.Store.Connect (Connected, connect)
import Halogen.Store.Monad (class MonadStore)
import Halogen.Store.Select (selectEq)
import Routing.Duplex as RD
import Routing.Hash (getHash)
import Type.Proxy (Proxy(..))
import Uniswap.Capability.Funds (class ManageFunds)
import Uniswap.Capability.Navigate (class Navigate, navigate)
import Uniswap.Capability.Pool (class ManagePool)
import Uniswap.Capability.Swap (class ManageSwap)
import Uniswap.Capability.Timer (class Timer)
import Uniswap.Data.Route (Route(..), routeCodec)
import Uniswap.Data.Wallet (Wallet)
import Uniswap.Page.AddLiquidityPool as AddLiquidityPool
import Uniswap.Page.ConnectWallet as CW
import Uniswap.Page.Funds as Funds
import Uniswap.Page.LiquidityPools as LiquidityPools
import Uniswap.Page.Swap as Swap
import Uniswap.Store as Store

type OpaqueSlot slot
  = forall query. H.Slot query Void slot

data Query a
  = Navigate Route a

type State
  = { route :: Maybe Route
    , currentWallet :: Maybe Wallet
    }

data Action
  = Initialize
  | Receive (Connected (Maybe Wallet) Unit)

type ChildSlots
  = ( home :: OpaqueSlot Unit
    , pools :: OpaqueSlot Unit
    , connect :: OpaqueSlot Unit
    , add :: OpaqueSlot Unit
    , funds :: OpaqueSlot Unit
    , swap :: OpaqueSlot Unit
    )

component ::
  forall m.
  MonadAff m =>
  MonadStore Store.Action Store.Store m =>
  Navigate m =>
  ManagePool m =>
  ManageFunds m =>
  ManageSwap m =>
  Timer m =>
  H.Component Query Unit Void m
component =
  connect (selectEq _.currentWallet)
    $ H.mkComponent
        { initialState: \{ context: currentWallet } -> { route: Nothing, currentWallet }
        , render
        , eval:
            H.mkEval
              $ H.defaultEval
                  { handleQuery = handleQuery
                  , handleAction = handleAction
                  , receive = Just <<< Receive
                  , initialize = Just Initialize
                  }
        }
  where
  handleAction :: Action -> H.HalogenM State Action ChildSlots Void m Unit
  handleAction = case _ of
    Initialize -> do
      initialRoute <- hush <<< (RD.parse routeCodec) <$> liftEffect getHash
      navigate $ fromMaybe Home initialRoute
    Receive { context: currentWallet } -> H.modify_ _ { currentWallet = currentWallet }

  handleQuery :: forall a. Query a -> H.HalogenM State Action ChildSlots Void m (Maybe a)
  handleQuery = case _ of
    Navigate dest a -> do
      { route } <- H.get
      -- do not rerender page if route is unchanged
      when (route /= Just dest) do
        H.modify_ _ { route = Just dest }
      pure (Just a)

  connected :: Maybe Wallet -> H.ComponentHTML Action ChildSlots m -> H.ComponentHTML Action ChildSlots m
  connected mbWallet html = case mbWallet of
    Nothing -> HH.slot (Proxy :: _ "connect") unit CW.component { redirect: false } absurd
    Just _ -> html

  render :: State -> H.ComponentHTML Action ChildSlots m
  render { route, currentWallet } = case route of
    Just r -> case r of
      Home ->
        connected currentWallet do
          HH.slot_ (Proxy :: _ "swap") unit Swap.component unit
      Pools ->
        connected currentWallet do
          HH.slot_ (Proxy :: _ "pools") unit LiquidityPools.component unit
      AddPool ->
        connected currentWallet do
          HH.slot_ (Proxy :: _ "add") unit AddLiquidityPool.component unit
      ConnectWallet -> HH.slot_ (Proxy :: _ "connect") unit CW.component { redirect: true }
      Funds ->
        connected currentWallet do
          HH.slot_ (Proxy :: _ "funds") unit Funds.component unit
      Swap ->
        connected currentWallet do
          HH.slot_ (Proxy :: _ "swap") unit Swap.component unit
    Nothing -> HH.div_ [ HH.text "Page Not Found" ]
