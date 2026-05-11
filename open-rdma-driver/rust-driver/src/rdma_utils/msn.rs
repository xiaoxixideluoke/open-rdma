#![allow(clippy::all)]

use std::{cmp::Ordering, ops::Sub};

use crate::constants::MAX_SEND_WR;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Msn(pub(crate) u16);

impl Msn {
    pub(crate) fn distance(self, rhs: Self) -> usize {
        self.0.wrapping_sub(rhs.0) as usize
    }

    #[allow(clippy::expect_used)]
    /// Advances the MSN by the given delta.
    ///
    /// # Panics
    ///
    /// Panics if the delta cannot be converted to a u16.
    pub(crate) fn advance(self, dlt: usize) -> Self {
        let x = self
            .0
            .wrapping_add(u16::try_from(dlt).expect("invalid delta"));
        Self(x)
    }
}

impl PartialOrd for Msn {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        let x = self.0.wrapping_sub(other.0);
        Some(match x {
            0 => Ordering::Equal,
            x if x as usize > MAX_SEND_WR => Ordering::Less,
            _ => Ordering::Greater,
        })
    }
}

impl Sub for Msn {
    type Output = Self;

    fn sub(self, rhs: Self) -> Self::Output {
        Self(self.0.wrapping_sub(rhs.0))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn msn_distance() {
        let msn1 = Msn(100);
        let msn2 = Msn(50);
        assert_eq!(msn1.distance(msn2), 50);

        let msn1 = Msn(10);
        let msn2 = Msn(0xFFFA);
        assert_eq!(msn1.distance(msn2), 16);
    }

    #[test]
    fn msn_advance() {
        let msn = Msn(100);
        let result = msn.advance(50);
        assert_eq!(result.0, 150);

        // Test wrapping
        let msn = Msn(0xFFFF);
        let result = msn.advance(1);
        assert_eq!(result.0, 0);
    }

    #[test]
    #[should_panic(expected = "invalid delta")]
    fn msn_advance_panic() {
        let msn = Msn(100);
        msn.advance(usize::MAX);
    }

    #[test]
    fn msn_ordering() {
        let msn1 = Msn(100);
        let msn2 = Msn(200);
        assert_eq!(msn1.partial_cmp(&msn2), Some(Ordering::Less));
        assert_eq!(msn2.partial_cmp(&msn1), Some(Ordering::Greater));
        assert_eq!(msn1.partial_cmp(&msn1), Some(Ordering::Equal));

        let msn1 = Msn(0);
        let msn2 = Msn((MAX_SEND_WR + 1) as u16);
        assert_eq!(msn1.partial_cmp(&msn2), Some(Ordering::Greater));
    }

    #[test]
    fn msn_sub() {
        let msn1 = Msn(150);
        let msn2 = Msn(50);
        let result = msn1 - msn2;
        assert_eq!(result.0, 100);

        let msn1 = Msn(10);
        let msn2 = Msn(20);
        let result = msn1 - msn2;
        assert_eq!(result.0, 0xFFF6);
    }
}
