import React from 'react';
import { useSelector, useDispatch } from 'react-redux';
import {
  View,
  Text,
  Button,
  FlatList,
  StyleSheet,
  Image,
  Alert,
} from 'react-native';
import { RootState, AppDispatch } from '../redux';
import { increment, decrement, removeFromCart } from '../redux/cartSlice';

const CartScreen = () => {
  const dispatch = useDispatch<AppDispatch>();
  const cartItems = useSelector((state: RootState) => state.cart.items);

  const totalPrice = cartItems.reduce(
    (total, item) => total + item.price * item.quantity,
    0,
  );

  const renderItem = ({ item }: any) => (
    <View style={styles.item}>
      <Image source={{ uri: item.imageUrl }} style={styles.image} />
      <View style={styles.details}>
        <Text style={styles.title}>{item.title}</Text>
        <Text>Price: ${item.price.toFixed(2)}</Text>
        <Text>Quantity: {item.quantity}</Text>
        <View style={styles.buttons}>
          <Button title="+" onPress={() => dispatch(increment(item.id))} />
          <Button title="-" onPress={() => dispatch(decrement(item.id))} />
          <Button
            title="Remove"
            color="red"
            onPress={() => dispatch(removeFromCart(item.id))}
          />
        </View>
      </View>
    </View>
  );

  return (
    <View style={styles.container}>
      <FlatList
        data={cartItems}
        keyExtractor={item => item.id}
        renderItem={renderItem}
        ListEmptyComponent={<Text style={styles.empty}>Your cart is empty.</Text>}
      />

      <View style={styles.totalContainer}>
        <Text style={styles.totalText}>Total: ${totalPrice.toFixed(2)}</Text>
        <Button
          title="Checkout"
          onPress={() => Alert.alert('Checkout', 'Proceeding to checkout...')}
        />
      </View>
    </View>
  );
};

export default CartScreen;

const styles = StyleSheet.create({
  container: { flex: 1, padding: 12, backgroundColor: '#fff' },
  item: {
    flexDirection: 'row',
    marginBottom: 12,
    backgroundColor: '#f9f9f9',
    borderRadius: 6,
    padding: 10,
    elevation: 1,
  },
  image: { width: 60, height: 60, borderRadius: 6, marginRight: 10 },
  details: { flex: 1 },
  title: { fontSize: 16, fontWeight: 'bold', marginBottom: 4 },
  buttons: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 8 },
  totalContainer: {
    borderTopWidth: 1,
    borderColor: '#ccc',
    paddingTop: 16,
    paddingBottom: 24,
    paddingHorizontal: 12,
    backgroundColor: '#fff',
  },
  totalText: { fontSize: 18, fontWeight: 'bold', marginBottom: 12 },
  empty: { textAlign: 'center', marginTop: 32, fontSize: 16, color: '#777' },
});
