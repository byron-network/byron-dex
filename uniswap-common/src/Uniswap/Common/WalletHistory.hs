{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
module Uniswap.Common.WalletHistory
  ( History(..)
  , HistoryId
  , getHistory
  , append
  , remove
  , lookup
  ) where

import Playground.Contract (FromJSON, Generic, ToJSON)
import PlutusTx.Prelude    (ByteString, Maybe, filter, find, flip, fst, map, notElem, snd, ($), (.), (<$>),
                            (==))
import Prelude             (Eq, Monoid (..), Semigroup (..), Show)

type HistoryId = ByteString
data History a = History [(HistoryId, a)] [HistoryId]
  deriving ( Eq
           , Show
           , Generic
           , FromJSON
           , ToJSON
           )

getHistory :: History a -> [a]
getHistory (History as _) = map snd as

append :: HistoryId -> a -> History a
append hid h = History [(hid, h)] []

remove :: HistoryId -> History a
remove hid = History [] [hid]

lookup :: HistoryId -> History a -> Maybe a
lookup hid (History hs _) = snd <$> find (\h' -> hid == fst h') hs

instance Semigroup (History a) where
   History as1 bs1 <> History as2 bs2 = History as3 bs3
      where
        as = as1 <> as2
        bs = bs1 <> bs2
        as3 = filter (flip notElem bs . fst) as
        bs3 = filter (flip notElem $ fst `map` as) bs

instance Monoid (History a) where
   mempty = History [] []


