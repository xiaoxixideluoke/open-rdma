#![allow(clippy::all)]

use std::{
    cmp::Ordering,
    fmt::Display,
    ops::{Add, AddAssign, Sub, SubAssign},
};

use crate::constants::{MAX_PSN_WINDOW, PSN_MASK};

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Psn(pub(crate) u32);

impl Psn {
    pub(crate) fn into_inner(self) -> u32 {
        self.0
    }
}

impl From<u32> for Psn {
    fn from(value: u32) -> Self {
        Self(value)
    }
}

impl PartialOrd for Psn {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Psn {
    fn cmp(&self, other: &Self) -> Ordering {
        let x = self.0.wrapping_sub(other.0) & PSN_MASK;
        match x {
            0 => Ordering::Equal,
            x if x as usize > MAX_PSN_WINDOW => Ordering::Less,
            _ => Ordering::Greater,
        }
    }
}

impl Add<u32> for Psn {
    type Output = Psn;

    fn add(self, rhs: u32) -> Self::Output {
        Psn(self.0.wrapping_add(rhs) & PSN_MASK)
    }
}

impl Add<Psn> for Psn {
    type Output = Psn;

    fn add(self, rhs: Psn) -> Self::Output {
        Psn(self.0.wrapping_add(rhs.0) & PSN_MASK)
    }
}

impl AddAssign<u32> for Psn {
    fn add_assign(&mut self, rhs: u32) {
        self.0 = self.0.wrapping_add(rhs) & PSN_MASK;
    }
}

impl AddAssign<Psn> for Psn {
    fn add_assign(&mut self, rhs: Psn) {
        self.0 = self.0.wrapping_add(rhs.0) & PSN_MASK;
    }
}

impl Sub<u32> for Psn {
    type Output = Psn;

    fn sub(self, rhs: u32) -> Self::Output {
        Psn(self.0.wrapping_sub(rhs) & PSN_MASK)
    }
}

impl Sub<Psn> for Psn {
    type Output = Psn;

    fn sub(self, rhs: Psn) -> Self::Output {
        Psn(self.0.wrapping_sub(rhs.0) & PSN_MASK)
    }
}

impl SubAssign<u32> for Psn {
    fn sub_assign(&mut self, rhs: u32) {
        self.0 = self.0.wrapping_sub(rhs) & PSN_MASK;
    }
}

impl SubAssign<Psn> for Psn {
    fn sub_assign(&mut self, rhs: Psn) {
        self.0 = self.0.wrapping_sub(rhs.0) & PSN_MASK;
    }
}

impl Display for Psn {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn psn_add_u32() {
        let psn = Psn(100);
        let result = psn + 50;
        assert_eq!(result.0, 150);

        let psn = Psn(PSN_MASK);
        let result = psn + 1;
        assert_eq!(result.0, 0);
    }

    #[test]
    fn psn_add_psn() {
        let psn1 = Psn(100);
        let psn2 = Psn(50);
        let result = psn1 + psn2;
        assert_eq!(result.0, 150);

        let psn1 = Psn(PSN_MASK);
        let psn2 = Psn(1);
        let result = psn1 + psn2;
        assert_eq!(result.0, 0);
    }

    #[test]
    fn psn_add_assign_u32() {
        let mut psn = Psn(100);
        psn += 50;
        assert_eq!(psn.0, 150);

        let mut psn = Psn(PSN_MASK);
        psn += 1;
        assert_eq!(psn.0, 0);
    }

    #[test]
    fn psn_add_assign_psn() {
        let mut psn1 = Psn(100);
        let psn2 = Psn(50);
        psn1 += psn2;
        assert_eq!(psn1.0, 150);

        let mut psn1 = Psn(PSN_MASK);
        let psn2 = Psn(1);
        psn1 += psn2;
        assert_eq!(psn1.0, 0);
    }

    #[test]
    fn psn_sub_u32() {
        let psn = Psn(150);
        let result = psn - 50;
        assert_eq!(result.0, 100);

        let psn = Psn(0);
        let result = psn - 1;
        assert_eq!(result.0, PSN_MASK);
    }

    #[test]
    fn psn_sub_psn() {
        let psn1 = Psn(150);
        let psn2 = Psn(50);
        let result = psn1 - psn2;
        assert_eq!(result.0, 100);

        let psn1 = Psn(0);
        let psn2 = Psn(1);
        let result = psn1 - psn2;
        assert_eq!(result.0, PSN_MASK);
    }

    #[test]
    fn psn_sub_assign_u32() {
        let mut psn = Psn(150);
        psn -= 50;
        assert_eq!(psn.0, 100);

        let mut psn = Psn(0);
        psn -= 1;
        assert_eq!(psn.0, PSN_MASK);
    }

    #[test]
    fn psn_sub_assign_psn() {
        let mut psn1 = Psn(150);
        let psn2 = Psn(50);
        psn1 -= psn2;
        assert_eq!(psn1.0, 100);

        let mut psn1 = Psn(0);
        let psn2 = Psn(1);
        psn1 -= psn2;
        assert_eq!(psn1.0, PSN_MASK);
    }

    #[test]
    fn psn_ordering() {
        assert_eq!(Psn(100).cmp(&Psn(100)), Ordering::Equal);
        assert_eq!(Psn(101).cmp(&Psn(100)), Ordering::Greater);
        assert_eq!(Psn(100).cmp(&Psn(101)), Ordering::Less);

        assert_eq!(Psn(0).cmp(&Psn((1 << 24) - 1)), Ordering::Greater);
        assert_eq!(Psn((1 << 24) - 1).cmp(&Psn(0)), Ordering::Less);
    }
}
