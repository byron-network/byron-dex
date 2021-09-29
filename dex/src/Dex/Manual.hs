{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE TypeApplications   #-}

module Dex.Manual where

import           Data.Default
import           Data.Functor           (void)
import qualified Data.Map               as Map
import           Dex.OffChain
import           Dex.Types
import           Plutus.Trace.Emulator  as Emulator
import qualified Plutus.V1.Ledger.Ada   as Ada
import qualified Plutus.V1.Ledger.Value as Value
import           Wallet.Emulator.Wallet as Wallet


customSymbol :: [Char]
customSymbol = "ff"

customToken :: [Char]
customToken = "PLN"

customSymbolsAndTokens :: [(Value.CurrencySymbol, Value.TokenName)]
customSymbolsAndTokens = [("ff", "coin1"), ("ee", "coin2"), ("dd", "coin3"), ("cc", "coin4"), ("bb", "coin5")]


customSymbol2 :: [Char]
customSymbol2 = "ee"

customToken2 :: [Char]
customToken2 = "BTC"

customSymbol3 :: [Char]
customSymbol3 = "dd"

customToken3 :: [Char]
customToken3 = "ETH"

main :: IO ()
main = runTrace dexTrace

runTrace :: EmulatorTrace () -> IO ()
runTrace = runEmulatorTraceIO' def emulatorCfg def
  where
    emulatorCfg = EmulatorConfig $ Left $ Map.fromList ([(Wallet i, v) | i <- [1 .. 4]])
      where
        v = Ada.lovelaceValueOf 100_000_000 <> mconcat (map (\(symbol,tokenName) -> Value.singleton symbol tokenName 100_000_000) customSymbolsAndTokens)




dexTrace :: EmulatorTrace ()
dexTrace = do
  h1 <- activateContractWallet (Wallet 1) dexEndpoints
  h2 <- activateContractWallet (Wallet 2) dexEndpoints
  void $ callEndpoint @"sell" h1 (WithHistoryId "a" (SellOrderParams (Value.AssetClass ("ff", "coin1")) (Value.AssetClass ("ee", "coin2")) (1,2) 100))
  void $ waitNSlots 10
  void $ callEndpoint @"sell" h1 (WithHistoryId "b" (SellOrderParams (Value.AssetClass ("ff", "coin1")) (Value.AssetClass ("ee", "coin2")) (1,2) 200))
  void $ waitNSlots 10
  void $ callEndpoint @"perform" h2 (WithHistoryId "c" ())
  void $ waitNSlots 10
