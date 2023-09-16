{-# LANGUAGE UndecidableInstances #-}

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

{- |
Copyright   :  (c) 2023 Yamada Ryo
License     :  MPL-2.0 (see the file LICENSE)
Maintainer  :  ymdfield@outlook.jp
Stability   :  experimental
Portability :  portable
-}
module Control.Effect.Class.Writer where

class Monoid w => Tell w f where
    tell :: w -> f ()

class Monoid w => WriterH w f where
    listen :: f a -> f (a, w)
    cencor :: (w -> w) -> f a -> f a

makeEffect "Writer" ''Tell ''WriterH
