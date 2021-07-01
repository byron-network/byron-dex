{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}
{-| Example trace for the uniswap contract
-}
module Uniswap.Trace(
      setupTokens
    , tokenNames
    , wallets
    ) where

import           Control.Monad             (forM_, when)
import           Control.Monad.Freer.Error (throwError)
import qualified Data.Map                  as Map
import qualified Data.Monoid               as Monoid
import qualified Data.Semigroup            as Semigroup
import           Ledger
import           Ledger.Ada                (adaSymbol, adaToken)
import           Ledger.Constraints
import           Ledger.Value              as Value
import           Plutus.Contract           hiding (throwError)
import qualified Plutus.Contracts.Currency as Currency
import           Plutus.Trace.Emulator     (EmulatorRuntimeError (GenericError),
                                            EmulatorTrace)
import qualified Plutus.Trace.Emulator     as Emulator
import           Uniswap.OffChain          as OffChain
import           Uniswap.Types             as Types
import           Wallet.Emulator.Types     (Wallet (..), walletPubKey)


-- | Create some sample tokens and distribute them to
--   the emulated wallets
setupTokens :: Contract (Maybe (Semigroup.Last Currency.OneShotCurrency)) Currency.CurrencySchema Currency.CurrencyError ()
setupTokens = do
    ownPK <- pubKeyHash <$> ownPubKey
    cur   <- Currency.forgeContract ownPK [(tn, fromIntegral (length wallets) * amount) | tn <- tokenNames]
    let cs = Currency.currencySymbol cur
        v  = mconcat [Value.singleton cs tn amount | tn <- tokenNames]
    forM_ wallets $ \w -> do
        let pkh = pubKeyHash $ walletPubKey w
        Control.Monad.when (pkh /= ownPK) $ do
            tx <- submitTx $ mustPayToPubKey pkh v
            awaitTxConfirmed $ txId tx
    tell $ Just $ Semigroup.Last cur
  where
    amount = 1000000

wallets :: [Wallet]
wallets = [Wallet i | i <- [1 .. 4]]

tokenNames :: [TokenName]
tokenNames = ["A", "B", "C", "D"]