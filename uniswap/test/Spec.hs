module Main
    ( main
    ) where

import qualified Spec.Model

import           Test.Tasty

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Uniswap"
    [ Spec.Model.tests
    ]