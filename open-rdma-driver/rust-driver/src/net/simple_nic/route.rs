use std::{io, net::Ipv4Addr};

use netlink_packet_core::{NetlinkMessage, NLM_F_ACK, NLM_F_CREATE, NLM_F_EXCL, NLM_F_REQUEST};
use netlink_packet_route::{
    route::{
        RouteAddress, RouteAttribute, RouteHeader, RouteMessage, RouteProtocol, RouteScope,
        RouteType,
    },
    AddressFamily, RouteNetlinkMessage,
};
use netlink_sys::{protocols::NETLINK_ROUTE, Socket, SocketAddr};

/// A handle for managing routing functionality
pub(super) struct RouteHandle {
    /// The underlying netlink socket
    inner: Socket,
}

impl RouteHandle {
    /// Creates a new `RouteHandle`
    pub(super) fn new() -> io::Result<Self> {
        let mut socket = Socket::new(NETLINK_ROUTE)?;
        let _addr = socket.bind_auto()?;
        let kernel_addr = SocketAddr::new(0, 0);
        socket.connect(&kernel_addr)?;
        Ok(Self { inner: socket })
    }

    /// Adds a new IPv4 route to the routing table.
    pub(super) fn add_route_v4(
        &self,
        dest_addr: Ipv4Addr,
        prefix_length: u8,
        gateway_addr: Ipv4Addr,
    ) -> io::Result<()> {
        let message = Self::build_route_message_v4(dest_addr, prefix_length, gateway_addr);
        let mut req = NetlinkMessage::from(RouteNetlinkMessage::NewRoute(message));
        req.header.flags = NLM_F_REQUEST | NLM_F_ACK | NLM_F_EXCL | NLM_F_CREATE;
        req.finalize();
        let len = req.buffer_len();
        let mut buffer = vec![0; len];
        req.serialize(&mut buffer);
        let n = self.inner.send(&buffer, 0)?;
        assert_eq!(n, len, "failed to send entire buffer");

        Ok(())
    }

    /// Builds a route message for IPv4 routing
    fn build_route_message_v4(
        dest_addr: Ipv4Addr,
        prefix_length: u8,
        gateway_addr: Ipv4Addr,
    ) -> RouteMessage {
        let mut message = RouteMessage::default();
        message.header.table = RouteHeader::RT_TABLE_MAIN;
        message.header.protocol = RouteProtocol::Static;
        message.header.scope = RouteScope::Universe;
        message.header.kind = RouteType::Unicast;
        message.header.address_family = AddressFamily::Inet;
        message.header.destination_prefix_length = prefix_length;
        message
            .attributes
            .push(RouteAttribute::Destination(RouteAddress::Inet(dest_addr)));
        message
            .attributes
            .push(RouteAttribute::Gateway(RouteAddress::Inet(gateway_addr)));
        message
    }
}
