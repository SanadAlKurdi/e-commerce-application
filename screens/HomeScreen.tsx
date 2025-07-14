import React, { useCallback, useEffect, useLayoutEffect, useState } from 'react';
import {
  ActivityIndicator,
  Button,
  FlatList,
  Image,
  StyleSheet,
  Text,
  TextInput,
  View,
  TouchableOpacity,
  Alert,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useDispatch, useSelector } from 'react-redux';
import { NativeModules } from 'react-native';

import { fetchProducts, Product } from '../services/firebaseService';
import { RootStackParamList } from '../navigation/AppNavigator';
import { RootState, AppDispatch } from '../redux';
import { addToCart } from '../redux/cartSlice';

const { AuthModule } = NativeModules;

const HomeScreen = () => {
  const [search, setSearch] = useState('');
  const [products, setProducts] = useState<Product[]>([]);
  const [lastDoc, setLastDoc] = useState<any>(null);
  const [loading, setLoading] = useState(false);

  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const dispatch = useDispatch<AppDispatch>();
  const cartItems = useSelector((state: RootState) => state.cart.items);

  const cartCount = cartItems.reduce((sum, item) => sum + item.quantity, 0);

  const handleLogout = useCallback(async () => {
    try {
      await AuthModule.logout();
      navigation.replace('Login');
    } catch (error: any) {
      Alert.alert('Logout Failed', error.message || 'Unknown error');
    }
  }, [navigation]);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <View style={styles.headerRightContainer}>
          <TouchableOpacity onPress={() => navigation.navigate('CartScreen')}>
            <Text style={styles.cartIcon}>🛒 ({cartCount})</Text>
          </TouchableOpacity>
          <TouchableOpacity onPress={handleLogout}>
            <Text style={styles.logout}>Logout</Text>
          </TouchableOpacity>
        </View>
      ),
    });
  }, [navigation, cartCount, handleLogout]);

  const loadProducts = useCallback(async () => {
    if (loading) return;
    setLoading(true);
    try {
      const { data, lastDoc: newLastDoc } = await fetchProducts(lastDoc, search);
      setProducts(prev => [...prev, ...data]);
      setLastDoc(newLastDoc);
    } catch (error) {
      console.error('Error fetching products:', error);
    } finally {
      setLoading(false);
    }
  }, [lastDoc, search, loading]);

  useEffect(() => {
    setProducts([]);
    setLastDoc(null);
    loadProducts();
  }, [search, loadProducts]);

  const renderItem = ({ item }: { item: Product }) => {
    if (!item.id) return null;

    return (
      <View style={styles.card}>
        <Image source={{ uri: item.imageUrl }} style={styles.image} />
        <View style={styles.info}>
          <Text style={styles.title}>{item.title}</Text>
          <Text>${item.price.toFixed(2)}</Text>
          <Button
            title="Add to Cart"
            onPress={() =>
              dispatch(
                addToCart({
                  id: item.id!,
                  title: item.title,
                  price: item.price,
                  imageUrl: item.imageUrl,
                  quantity: 1,
                })
              )
            }
          />
        </View>
      </View>
    );
  };

  return (
    <View style={styles.container}>
      <TextInput
        placeholder="Search products..."
        style={styles.searchInput}
        value={search}
        onChangeText={setSearch}
      />
      <Button title="Add Product" onPress={() => navigation.navigate('CreateProductScreen')} />
      <FlatList
        data={products}
        renderItem={renderItem}
        keyExtractor={item => item.id!}
        onEndReached={loadProducts}
        onEndReachedThreshold={0.5}
        ListFooterComponent={loading ? <ActivityIndicator size="small" /> : null}
      />
    </View>
  );
};

export default HomeScreen;

const styles = StyleSheet.create({
  container: { flex: 1, padding: 10, backgroundColor: '#fff' },
  searchInput: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 6,
    padding: 10,
    marginBottom: 10,
  },
  card: {
    flexDirection: 'row',
    padding: 12,
    marginBottom: 10,
    borderRadius: 6,
    backgroundColor: '#f8f8f8',
    elevation: 1,
  },
  image: { width: 60, height: 60, borderRadius: 6, marginRight: 10 },
  info: { justifyContent: 'center', flex: 1 },
  title: { fontSize: 16, fontWeight: 'bold' },
  cartIcon: {
    fontSize: 18,
    marginRight: 10,
  },
  logout: {
    fontSize: 16,
    color: 'red',
    marginLeft: 10,
  },
  headerRightContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
});
